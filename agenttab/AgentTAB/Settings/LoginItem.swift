import ServiceManagement

enum LoginItem {
    static func register() {
        try? SMAppService.mainApp.register()
    }
    static func unregister() {
        try? SMAppService.mainApp.unregister()
    }
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
