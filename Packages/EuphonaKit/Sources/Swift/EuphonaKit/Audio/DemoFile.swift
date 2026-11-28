#if DEBUG
import Foundation

/// A file named by a development launch argument (`-demo_audio`, `-demo_import`, `-demo_input`): an
/// absolute path as given, a relative one inside the app bundle.
public enum DemoFile {
    public static func url(for key: String) -> URL? {
        UserDefaults.standard.string(forKey: key).map { path in
            path.hasPrefix("/") ? URL(filePath: path) : Bundle.main.bundleURL.appending(path: path)
        }
    }
}
#endif
