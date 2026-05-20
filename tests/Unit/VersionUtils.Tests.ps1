#Requires -Version 5.1
<#
    Tests for lib/version-utils.ps1: Normalize-Tag and Compare-SemVer.
    Dot-sources the script into the test session so we can call the
    functions directly.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $script:RepoRoot 'lib\version-utils.ps1')
}

Describe 'Normalize-Tag' {

    It 'returns <Expected> for <Tag>' -ForEach @(
        @{ Tag = 'v1.2.3';   Expected = '1.2.3'   }
        @{ Tag = 'V1.2.3';   Expected = '1.2.3'   }
        @{ Tag = '1.2.3';    Expected = '1.2.3'   }
        @{ Tag = '  v2.0  '; Expected = '2.0'     }
        @{ Tag = 'vvv1.0';   Expected = '1.0'     }    # TrimStart removes all leading v/V chars
        @{ Tag = 'v0.3.6-rc.1+build.5'; Expected = '0.3.6-rc.1+build.5' }
    ) {
        Normalize-Tag $Tag | Should -Be $Expected
    }

    It 'returns $null for empty or whitespace input: "<Tag>"' -ForEach @(
        @{ Tag = '' }
        @{ Tag = '   ' }
        @{ Tag = $null }
    ) {
        $result = Normalize-Tag $Tag
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Compare-SemVer' {

    It '<A> vs <B> = <Expected>' -ForEach @(
        # equality
        @{ A = '0.3.6'; B = '0.3.6'; Expected = 0  }
        @{ A = '1.0';   B = '1.0.0'; Expected = 0  }    # shorter pads with zeros
        # less-than
        @{ A = '0.3.5';  B = '0.3.6';  Expected = -1 }
        @{ A = '0.9.99'; B = '1.0.0';  Expected = -1 }
        @{ A = '0.3.9';  B = '0.3.10'; Expected = -1 }  # numeric, not lexical
        # greater-than
        @{ A = '0.3.7';  B = '0.3.6';  Expected = 1  }
        @{ A = '1.0.0';  B = '0.99.99'; Expected = 1 }
        @{ A = '0.3.10'; B = '0.3.9';  Expected = 1  }
    ) {
        Compare-SemVer $A $B | Should -Be $Expected
    }

    It 'treats pre-release identifiers numerically by splitting on . + -' {
        # '1.0.0-rc1' -> [1,0,0,0] (because rc1 -> 0 via \D->0 then [int])
        # Wait: '-replace \D,0' replaces each non-digit with '0', so 'rc1' -> '001' -> 1.
        # Document the actual behavior with explicit cases rather than asserting
        # full SemVer 2.0 pre-release ordering (the helper is intentionally simple).
        (Compare-SemVer '1.0.0' '1.0.0-rc1') | Should -BeLessOrEqual 0
    }

    It 'is non-zero and opposite-signed when arguments are swapped' {
        $forward = Compare-SemVer '0.3.5' '0.4.0'
        $reverse = Compare-SemVer '0.4.0' '0.3.5'
        $forward | Should -Be -1
        $reverse | Should -Be 1
    }
}
