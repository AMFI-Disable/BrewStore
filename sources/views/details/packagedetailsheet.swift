import Foundation

enum PackageDetailSheet: Identifiable {
    case removal(BrewStoreRemovalPlan)
    case visualGraph
    case advancedInstall
    case securityApproval
    case versionSwitcher
    case upgradeDiff
    case bottleIntegrity
    case caskQuarantine
    case sourceBuildStudio
    case blastRadius
    case showdown(BrewStorePackage)

    var id: String {
        switch self {
        case .removal:
            return "removal"
        case .visualGraph:
            return "visualGraph"
        case .advancedInstall:
            return "advancedInstall"
        case .securityApproval:
            return "securityApproval"
        case .versionSwitcher:
            return "versionSwitcher"
        case .upgradeDiff:
            return "upgradeDiff"
        case .bottleIntegrity:
            return "bottleIntegrity"
        case .caskQuarantine:
            return "caskQuarantine"
        case .sourceBuildStudio:
            return "sourceBuildStudio"
        case .blastRadius:
            return "blastRadius"
        case .showdown(let pkg):
            return "showdown-\(pkg.id)"
        }
    }
}
