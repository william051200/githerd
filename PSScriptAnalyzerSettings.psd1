@{
    # PSScriptAnalyzer settings for the githerd repo.
    #
    # Severity gate: CI fails on Error and Warning. Information findings are
    # reported but do not block.
    Severity     = @('Error','Warning')

    # Run every built-in rule by default, then turn off the ones that are
    # noise for this codebase.
    IncludeDefaultRules = $true

    ExcludeRules = @(
        # CLI tool: we deliberately Write-Host coloured progress to the user
        # terminal. Output is not meant to be captured or piped.
        'PSAvoidUsingWriteHost'

        # update-check.ps1 must never crash sync.bat; many catches are
        # intentionally empty so a flaky GitHub call or disk error is silently
        # absorbed.
        'PSAvoidUsingEmptyCatchBlock'

        # All non-cmdlet-shaped functions in this repo are private helpers
        # (Print-Hint, Get-LatestTag, Backup-Config, etc.). Renaming them to
        # approved verbs would not improve the public surface, since they
        # aren't exported.
        'PSUseApprovedVerbs'

        # Private helpers don't need -WhatIf/-Confirm.
        'PSUseShouldProcessForStateChangingFunctions'

        # False positives: PSScriptAnalyzer's data-flow analysis doesn't
        # follow closures. Several params (Quiet/DevZip/InstallScriptUrl) are
        # used by nested helper functions that read script-scope variables.
        'PSReviewUnusedParameter'

        # Style preference: we use plural nouns (Get-ZipEntries etc.) for
        # helpers that return collections. Not worth fighting.
        'PSUseSingularNouns'
    )
}
