import Foundation

func instrumentText(_ en: String, _ ja: String, _ zh: String) -> String {
    let language=Locale.preferredLanguages.first ?? "en"
    if language.hasPrefix("ja") { return ja }
    if language.hasPrefix("zh") { return zh }
    return en
}
