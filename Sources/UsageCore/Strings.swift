import Foundation

public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case es, en
}

/// Every user-facing string, in Spanish and English.
public struct Strings: Sendable {
    public let language: AppLanguage

    public static func `for`(_ language: AppLanguage) -> Strings { Strings(language: language) }

    private var isEs: Bool { language == .es }

    // MARK: Panel
    public var fiveHourLimit: String { isEs ? "Límite 5h" : "5h limit" }
    public var weekly: String { isEs ? "Semanal" : "Weekly" }
    public var noSessions: String { isEs ? "No hay sesiones de Claude Code abiertas" : "No open Claude Code sessions" }
    public var background: String { isEs ? "En segundo plano" : "Background" }
    public var refresh: String { isEs ? "Actualizar" : "Refresh" }
    public var quit: String { isEs ? "Salir" : "Quit" }
    public var openConfigHelp: String {
        isEs ? "Abrir config.json (los cambios se aplican solos)" : "Open config.json (changes apply automatically)"
    }
    public var languageHelp: String { isEs ? "Idioma" : "Language" }
    public var tokenExpired: String { isEs ? "Token expirado — abre Claude Code" : "Token expired — open Claude Code" }
    public var noToken: String {
        isEs ? "Sin sesión de Claude Code en el Keychain" : "No Claude Code login found in the Keychain"
    }
    public var limitsFailed: String { isEs ? "No se pudieron actualizar los límites" : "Couldn't update limits" }
    public var updatingLimits: String { isEs ? "Actualizando límites…" : "Updating limits…" }
    public var updatedJustNow: String { isEs ? "Actualizado hace un momento" : "Updated just now" }
    public func updatedMinutesAgo(_ m: Int) -> String {
        isEs ? "Actualizado hace \(m) min" : "Updated \(m) min ago"
    }
    public func resets(_ when: String) -> String { isEs ? "reinicia \(when)" : "resets \(when)" }
    public var noRepliesYet: String { isEs ? "Sin respuestas todavía" : "No replies yet" }
    public var confirmStop: String { isEs ? "¿Detener?" : "Stop?" }
    public var confirmStopHelp: String {
        isEs ? "Clic otra vez para detener; la conversación se conserva"
             : "Click again to stop; the conversation is kept"
    }
    public var openInTerminalHelp: String { isEs ? "Abrir en Terminal (claude attach)" : "Open in Terminal (claude attach)" }
    public var stopHelp: String { isEs ? "Detener sesión (claude stop)" : "Stop session (claude stop)" }
    public var stopFailedHelp: String { isEs ? "No se pudo detener; intenta de nuevo" : "Couldn't stop it; try again" }

    // MARK: Notifications
    public func contextTitle(_ threshold: Int, _ name: String) -> String {
        isEs ? "Contexto al \(threshold)% en \(name)" : "Context at \(threshold)% in \(name)"
    }
    public var considerNewChat: String { isEs ? "Considera iniciar un chat nuevo." : "Consider starting a new chat." }
    public var startNewChat: String { isEs ? "Inicia un chat nuevo." : "Start a new chat." }
    public func limitTitle(_ threshold: Int) -> String {
        isEs ? "Llevas \(threshold)% del límite de 5 horas" : "You've used \(threshold)% of your 5-hour limit"
    }
    public func resetsAt(_ time: String) -> String { isEs ? "Reinicia a las \(time)." : "Resets at \(time)." }
    public var resetsSoon: String { isEs ? "Reinicia pronto." : "Resets soon." }
    public func finishedTitle(_ name: String) -> String { isEs ? "✓ \(name) terminó" : "✓ \(name) finished" }
    public var finishedBody: String { isEs ? "Listo para tu siguiente mensaje." : "Ready for your next message." }
    public func waitingTitle(_ name: String) -> String {
        isEs ? "⏸ \(name) necesita tu respuesta" : "⏸ \(name) needs your input"
    }
    public var waitingBody: String {
        isEs ? "Claude está esperando tu permiso o respuesta." : "Claude is waiting for your permission or answer."
    }

    // MARK: Dates
    /// "3:40 p.m." / "3:40 PM"
    public func time(_ date: Date) -> String { format(date, "h:mm a") }
    /// "lun 15:40" / "Mon 15:40"
    public func weekdayTime(_ date: Date) -> String { format(date, "EEE H:mm") }

    private func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: isEs ? "es_MX" : "en_US")
        f.dateFormat = pattern
        // ICU uses narrow no-break spaces around AM/PM; plain spaces render the same and compare predictably.
        return f.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
