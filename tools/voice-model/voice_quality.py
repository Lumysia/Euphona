"""Voice quality measures, the same algorithms as the app's VoiceQuality.swift.

- Intensity: 10 ms frames inside speech, dB re 20 µPa with samples taken as pascals (Praat's convention).
- Pitch statistics over voiced SwiftF0 frames inside speech.
- HNR: normalized autocorrelation of 40 ms Hann windows divided by the window's own (Boersma 1993),
  on a 40 ms grid where the window centre is voiced.
- Jitter and shimmer: glottal cycles found by peak picking guided by the pitch track, within voiced
  runs; neighbours differing by more than 1.3x (periods) or 1.6x (amplitudes) are skipped, as in Praat.
- CPPS: cepstral peak prominence of 40 ms frames every 10 ms, smoothed over 7 frames and 3 quefrency
  bins, peak between 1/600 and 1/60 s, above a line fitted from 1 ms (Hillenbrand & Houde 1996).
"""

import numpy as np

from features import SAMPLE_RATE

F0_HOP = 256
F0_CENTRE = 127.5
MIN_HZ, MAX_HZ, MIN_CONFIDENCE = 75.0, 600.0, 0.9
WINDOW = 640
FFT = 2048
NAMES = ("hnr_db", "cpps_db", "jitter_local", "jitter_rap", "jitter_ppq5", "shimmer_local", "shimmer_apq3",
         "shimmer_apq5", "f0_median", "f0_iqr", "f0_cv", "voiced_fraction", "intensity_median", "intensity_iqr")


def in_speech(positions, segments):
    mask = np.zeros(len(positions), bool)
    for a, b in segments:
        mask |= (positions >= a) & (positions < b)
    return mask


def voiced_track(hz, confidence):
    return np.where((confidence >= MIN_CONFIDENCE) & (hz >= MIN_HZ) & (hz <= MAX_HZ), hz, np.nan)


def hnr_windows(samples, segments, track):
    """(start, end, hnr) on a 40 ms grid, hnr NaN where the centre is unvoiced or outside speech."""
    hann = np.hanning(WINDOW + 2)[1:-1]
    rw = np.fft.irfft(np.abs(np.fft.rfft(hann, FFT)) ** 2)[:WINDOW]
    rw = rw / rw[0]
    lo, hi = int(np.ceil(SAMPLE_RATE / MAX_HZ)), int(SAMPLE_RATE / MIN_HZ)
    out = []
    for start in range(0, len(samples) - WINDOW + 1, WINDOW):
        centre = start + WINDOW // 2
        frame = int(round((centre - F0_CENTRE) / F0_HOP))
        value = np.nan
        if 0 <= frame < len(track) and not np.isnan(track[frame]) and in_speech(np.array([centre]), segments)[0]:
            x = samples[start:start + WINDOW] - samples[start:start + WINDOW].mean()
            x = x * hann
            r = np.fft.irfft(np.abs(np.fft.rfft(x, FFT)) ** 2)[:WINDOW]
            if r[0] > 1e-12:
                r = (r / r[0]) / np.maximum(rw, 1e-6)
                peak = float(np.clip(r[lo:hi + 1].max(), 1e-6, 1 - 1e-6))
                value = 10 * np.log10(peak / (1 - peak))
        out.append((start, start + WINDOW, value))
    return out


def cycles(samples, segments, track):
    """Periods (s) and peak amplitudes per voiced run."""
    centres = np.arange(len(track)) * F0_HOP + F0_CENTRE
    voiced = ~np.isnan(track) & in_speech(centres, segments)
    runs, i = [], 0
    while i < len(track):
        if voiced[i]:
            j = i
            while j + 1 < len(track) and voiced[j + 1]:
                j += 1
            if j - i >= 2:
                runs.append((i, j))
            i = j + 1
        else:
            i += 1
    result = []
    for a, b in runs:
        first, last = int(centres[a]), min(int(centres[b]), len(samples) - 1)
        period = lambda p: SAMPLE_RATE / np.interp(p, centres[a:b + 1], track[a:b + 1])
        t0 = int(period(first))
        segment = samples[first:first + t0]
        if len(segment) < 2:
            continue
        positive = segment.max() >= -segment.min()
        sign = 1.0 if positive else -1.0
        p = first + int(np.argmax(sign * segment))
        periods, amps = [], [abs(samples[p])]
        while True:
            t = period(p)
            lo, hi = p + int(0.8 * t), p + int(np.ceil(1.2 * t))
            if hi >= last:
                break
            q = lo + int(np.argmax(sign * samples[lo:hi + 1]))
            periods.append((q - p) / SAMPLE_RATE)
            amps.append(abs(samples[q]))
            p = q
        if len(periods) >= 3:
            result.append((np.array(periods), np.array(amps[1:])))
    return result


def perturbation(series, factor=1.3):
    """local, 3-point and 5-point relative perturbation, pooled over runs."""
    local, p3, p5, means = [], [], [], []
    for x in series:
        ok_pair = np.maximum(x[1:], x[:-1]) / np.maximum(np.minimum(x[1:], x[:-1]), 1e-12) <= factor
        local += list(np.abs(np.diff(x))[ok_pair])
        for i in range(1, len(x) - 1):
            p3.append(abs(x[i] - x[i - 1:i + 2].mean()))
        for i in range(2, len(x) - 2):
            p5.append(abs(x[i] - x[i - 2:i + 3].mean()))
        means += list(x)
    mean = np.mean(means) if means else np.nan
    f = lambda v: float(np.mean(v) / mean) if v and mean > 0 else np.nan
    return f(local), f(p3), f(p5)


def cpps(samples, segments):
    hop, n = 160, 1024
    hann = np.hanning(WINDOW + 2)[1:-1]
    rows = []
    for a, b in segments:
        for start in range(a, b - WINDOW + 1, hop):
            x = samples[start:start + WINDOW] * hann
            db = 10 * np.log10(np.abs(np.fft.rfft(x, n)) ** 2 + 1e-12)
            c = np.fft.irfft(db, n)
            rows.append(20 * np.log10(np.abs(c[:n // 2]) + 1e-12))
    if len(rows) < 7:
        return np.nan
    c = np.array(rows)
    c = np.array([c[max(0, i - 3):i + 4].mean(0) for i in range(len(c))])
    c = np.stack([np.convolve(r, np.ones(3) / 3, mode="same") for r in c])
    q = np.arange(n // 2)
    lo, hi = int(np.ceil(SAMPLE_RATE / 600)), int(SAMPLE_RATE / 60)
    fit = (q >= SAMPLE_RATE // 1000)
    values = []
    for r in c:
        slope, intercept = np.polyfit(q[fit], r[fit], 1)
        k = lo + int(np.argmax(r[lo:hi + 1]))
        values.append(r[k] - (slope * k + intercept))
    return float(np.mean(values))


def measures(samples, segments, hz, confidence):
    track = voiced_track(hz, confidence)
    frame_positions = np.arange(len(track)) * F0_HOP + F0_CENTRE
    speech_frames = in_speech(frame_positions, segments)
    voiced = track[speech_frames & ~np.isnan(track)]
    hnr = np.array([h for _, _, h in hnr_windows(samples, segments, track)])
    cyc = cycles(samples, segments, track)
    jitter = perturbation([p for p, _ in cyc])
    shimmer = perturbation([a for _, a in cyc], factor=1.6)
    intensity = []
    for a, b in segments:
        for s in range(a, b - 160 + 1, 160):
            power = np.mean(samples[s:s + 160] ** 2)
            if power > 0:
                intensity.append(10 * np.log10(power / 4e-10))
    q = lambda v, p: float(np.percentile(v, p)) if len(v) else np.nan
    return np.array([
        float(np.nanmean(hnr)) if np.any(~np.isnan(hnr)) else np.nan,
        cpps(samples, segments),
        *jitter, *shimmer,
        q(voiced, 50), q(voiced, 75) - q(voiced, 25),
        float(np.std(voiced) / np.mean(voiced)) if len(voiced) else np.nan,
        float(len(voiced) / max(speech_frames.sum(), 1)),
        q(intensity, 50), q(intensity, 75) - q(intensity, 25),
    ], np.float32)
