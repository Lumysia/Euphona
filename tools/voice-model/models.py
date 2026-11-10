"""The timbre head, with its input normalization inside, so the exported ONNX takes raw embeddings."""

import torch
from torch import nn

EMBEDDING_DIMS = 192


class Timbre(nn.Module):
    """One window's raw ECAPA embedding -> probability on the timbre scale (0 masculine, 1 feminine)."""

    def __init__(self, hidden: int = 64, dropout: float = 0.2) -> None:
        super().__init__()
        self.net = nn.Sequential(nn.Linear(EMBEDDING_DIMS, hidden), nn.GELU(), nn.Dropout(dropout),
                                 nn.Linear(hidden, 1))

    def logits(self, embeddings: torch.Tensor) -> torch.Tensor:
        x = embeddings / embeddings.norm(dim=-1, keepdim=True).clamp_min(1e-12)
        return self.net(x).squeeze(-1)

    def forward(self, embeddings: torch.Tensor) -> torch.Tensor:
        return torch.sigmoid(self.logits(embeddings))
