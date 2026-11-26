import Foundation

/// The placeholder org, people, teams and repositories of the mock world. None is real.
public enum MockCast {
    // MARK: People

    public static let adaPark = Person(login: "ada-park", displayName: "Ada Park")
    public static let samRivera = Person(login: "sam-rivera", displayName: "Sam Rivera")
    public static let joLindqvist = Person(login: "jo-lindqvist", displayName: "Jo Lindqvist")
    public static let maxChen = Person(login: "max-chen", displayName: "Max Chen")
    public static let lenaOkafor = Person(login: "lena-okafor", displayName: "Lena Okafor")
    public static let tomasReyes = Person(login: "tomas-reyes", displayName: "Tomas Reyes")
    public static let miraHolm = Person(login: "mira-holm", displayName: "Mira Holm")
    public static let kaiDuarte = Person(login: "kai-duarte", displayName: "Kai Duarte")

    /// "You" in the mock world. A member of `@acme/security`.
    public static let robinQuill = Person(login: "robin-quill", displayName: "Robin Quill")

    /// The eight people who do most of the work.
    public static let corePeople = [adaPark, samRivera, joLindqvist, maxChen, lenaOkafor, tomasReyes, miraHolm, kaiDuarte]

    /// People who review now and then, so a pull request can ask 30 reviewers.
    public static let occasionalPeople: [Person] = [
        ("avery-stone", "Avery Stone"), ("bea-lund", "Bea Lund"), ("cal-mercer", "Cal Mercer"),
        ("dana-voss", "Dana Voss"), ("eli-brandt", "Eli Brandt"), ("faye-moreau", "Faye Moreau"),
        ("gus-albrecht", "Gus Albrecht"), ("hana-ito", "Hana Ito"), ("ivo-petrov", "Ivo Petrov"),
        ("june-calder", "June Calder"), ("kit-ramsey", "Kit Ramsey"), ("lior-segal", "Lior Segal"),
        ("nell-okoro", "Nell Okoro"), ("omar-haddad", "Omar Haddad"), ("pia-sorensen", "Pia Sorensen"),
        ("quinn-abara", "Quinn Abara"), ("rio-tanaka", "Rio Tanaka"), ("suki-wren", "Suki Wren"),
        ("tess-halloran", "Tess Halloran"), ("uma-krishnan", "Uma Krishnan"), ("vic-delacroix", "Vic Delacroix"),
        ("wes-ogden", "Wes Ogden"),
    ].map { Person(login: $0.0, displayName: $0.1) }

    public static let deployPreviewBot = Person(login: "deploy-preview-bot", displayName: "deploy-preview-bot", isBot: true)
    public static let coverageBot = Person(login: "coverage-bot", displayName: "coverage-bot", isBot: true)
    public static let ciBot = Person(login: "ci-bot", displayName: "ci-bot", isBot: true)
    public static let bots = [deployPreviewBot, coverageBot, ciBot]

    public static let agentOne = Person(login: "example-agent-one", displayName: "Example Agent One", isAgent: true)
    public static let agentTwo = Person(login: "example-agent-two", displayName: "Example Agent Two", isAgent: true)
    public static let agents = [agentOne, agentTwo]

    /// Everyone who is a person, the viewer included.
    public static let humans = corePeople + [robinQuill] + occasionalPeople

    /// Every account in the world.
    public static let everyone = humans + agents + bots

    // MARK: Teams

    public static let securityTeam = Team(organization: "acme", slug: "security", members: [robinQuill, lenaOkafor, kaiDuarte])
    public static let webPlatformTeam = Team(organization: "acme", slug: "web-platform", members: [miraHolm, maxChen, joLindqvist])
    public static let teams = [securityTeam, webPlatformTeam]

    public static let viewer = Viewer(person: robinQuill, teams: [securityTeam])

    // MARK: Repositories

    public static let organization = "acme"
    public static let api = Repository(owner: "acme", name: "api")
    public static let web = Repository(owner: "acme", name: "web")
    public static let infra = Repository(owner: "acme", name: "infra")
    public static let docs = Repository(owner: "acme", name: "docs")
    public static let repositories = [api, web, infra, docs]

    /// Each repository's CODEOWNERS file.
    public static func codeOwnerRules(for repository: Repository) -> [CodeOwnerRule] {
        switch repository {
        case api:
            [
                CodeOwnerRule(pattern: "auth/**", owners: [securityTeam.handle]),
                CodeOwnerRule(pattern: "billing/**", owners: [tomasReyes.handle]),
                CodeOwnerRule(pattern: "db/migrations/**", owners: [maxChen.handle]),
            ]
        case web:
            [
                CodeOwnerRule(pattern: "src/**", owners: [webPlatformTeam.handle]),
                CodeOwnerRule(pattern: "src/pages/billing/**", owners: [lenaOkafor.handle]),
            ]
        case infra:
            [
                CodeOwnerRule(pattern: "*.tf", owners: [tomasReyes.handle]),
                CodeOwnerRule(pattern: "k8s/**", owners: [kaiDuarte.handle]),
                CodeOwnerRule(pattern: "iam/**", owners: [securityTeam.handle]),
            ]
        case docs:
            [CodeOwnerRule(pattern: "docs/**", owners: [maxChen.handle])]
        default:
            []
        }
    }

    // MARK: Labels

    static let labelColors: [String: String] = [
        "auth": "5319e7", "security": "b60205", "bug": "d73a4a", "feature": "0e8a16",
        "refactor": "c5def5", "chore": "ededed", "performance": "fbca04", "docs": "0075ca",
        "dependencies": "0366d6", "needs-qa": "f9d0c4", "backport": "bfdadc", "billing": "1d76db",
        "webhooks": "006b75", "infra": "5a4fcf", "ui": "e99695", "accessibility": "7057ff",
        "coverage-dropped": "e4e669", "agent": "c2e0c6", "generated": "cccccc",
    ]

    static func label(_ name: String) -> Label {
        Label(name: name, color: labelColors[name] ?? "ededed")
    }

    static func person(login: String) -> Person? {
        everyone.first { $0.login == login }
    }

    static func team(handle: String) -> Team? {
        teams.first { $0.handle == handle }
    }
}
