extension SocialProfileCard {
    /** 用户自己设过的用户名；默认值（等于 profileId）返回 nil（Android `SocialProfileCard.username`）。 */
    public var username: String? {
        citypulsoId.trimmingCharacters(in: .whitespaces).isEmpty || citypulsoId == profileId ? nil : citypulsoId
    }
}
