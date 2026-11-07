// Apri all'accesso, con il servizio di sistema (SMAppService): compare in Impostazioni di Sistema > Generali > Elementi login.

import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Restituisce un messaggio d'errore leggibile, o nil se è andata.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return L("Non riesco a cambiare l'apertura all'accesso: %@", error.localizedDescription)
        }
    }
}
