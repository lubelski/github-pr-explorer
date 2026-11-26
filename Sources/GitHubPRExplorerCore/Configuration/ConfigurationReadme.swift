import Foundation

/// The files written into a new configuration folder besides the settings.
enum ConfigurationReadme {
    /// `README.md`, for a person or an agent who opens the folder.
    static let text = """
        # github-pr-explorer configuration

        Everything you can configure in github-pr-explorer is a file in this folder. The app's
        Settings window writes these same files, so you, an editor, or a coding agent can change
        them directly. The app watches the folder and applies a change as soon as it is saved.

        ## Files

        - `settings.json`: the general settings.
          - `formatVersion`: always `1`. Required.
          - `appearance`: `"system"`, `"light"` or `"dark"`.
          - `defaultLayout`: the id of the layout pull request pages open with, such as
            `"decision-first"` or `"tabbed"`.
          - `hidesBotEventsInActivity`: `true` to start Activity with bot events folded into one row.
          - `updatesAutomatically`: `true` for a release build to check for, download and install
            updates on its own. `false` to check only with Check for Updates.
          - `experiments`: features being tried, by name, such as `{"someExperiment": true}`.
            One left out is off.
          - `pullRequestSource`: `"mock"` for the built-in placeholder pull requests, or
            `"github"` to read real ones through the `gh` login on this Mac.
          - `syncIntervalSeconds`: how often the list of pull requests is checked while the
            source is GitHub, from 60 to 3600. Default 300.
          - `watchedRepositories`: repositories, as `"owner/name"`, whose every open pull
            request is fetched, besides the ones that involve you.
          A key left out takes its default. A key the app does not know makes the file invalid.
        - `shorthands.json`: short names drawn in place of repositories and people, so lists
          are quicker to scan. `formatVersion` (`1`) and `shorthands`, a list such as
          `{"kind": "repository", "for": "acme/web", "shorthand": "Web"}` or
          `{"kind": "person", "for": "ada-park", "shorthand": "Ada"}`. Display only: titles,
          comments, links and anything sent to GitHub are unchanged. Missing means none.
          `github-pr-explorer-ctl shorthands set` and Settings, Shorthands write it.
        - `layouts/<id>.json`: your own page layouts, one per file, named after the layout's id.
          A layout has `formatVersion` (`1`), `id` (lowercase letters, digits and hyphens),
          `name`, and `tabs`. A tab has `name` and `columns`. A column has `width` (a number
          above zero, relative to the other columns) and `blocks`. A block has `kind`
          (`description`, `checks`, `reviewers`, `ownersTouched`, `files`, `threads`, `activity`,
          `commits`, `labelsAndMetadata`) and `size` (`small` or `large`).
          The built-in layouts, `decision-first` and `tabbed`, are not copied here. A file with a
          built-in layout's id replaces it. To start from one, run
          `github-pr-explorer-ctl layouts duplicate tabbed my-layout`, or use Duplicate to Edit
          in Settings, Layouts.

        The JSON Schemas for each are in the app's repository, under `schemas/`.

        Pull request data fetched from GitHub is never kept here. It is a cache in the `index`
        folder next to this one, and deleting that folder is always safe.

        ## When a file is wrong

        A file that does not validate is not applied. The app keeps using the last version that
        worked and shows the problem in Settings, with the file, where in it, and what is wrong.
        Check your work with:

            github-pr-explorer-ctl config validate

        ## History

        This folder is a git repository. Every valid change is committed, whoever made it, with
        a message that says what changed and who made it: "Settings window", "edited on disk",
        or "ctl". To see and bring back versions:

            github-pr-explorer-ctl config history
            github-pr-explorer-ctl config diff <version>
            github-pr-explorer-ctl config restore <version> [file]

        Restoring adds a new version, so nothing is lost. Settings, History does the same.
        """

    /// `.gitignore`: files that are never configuration.
    static let gitignore = """
        .DS_Store
        *.swp
        *~

        """
}
