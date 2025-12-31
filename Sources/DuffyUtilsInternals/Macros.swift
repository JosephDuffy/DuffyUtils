import DuffyUtilsFoundation

@attached(accessor)
public macro GitConfigValue(
    name: String,
    location: GitConfigValueLocation = .default
) = #externalMacro(module: "DuffyUtilsMacros", type: "GitConfigValueMacro")
