import WidgetKit

enum WidgetReload {
    static func now() { WidgetCenter.shared.reloadAllTimelines() }
}
