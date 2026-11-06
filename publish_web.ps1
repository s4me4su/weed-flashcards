<#
.SYNOPSIS
  Builds the web version and publishes it to GitHub Pages.

.DESCRIPTION
  build_web.ps1 makes the bundle in build\web; this turns that folder into a
  `gh-pages` branch and pushes it, which is what GitHub Pages serves. The branch
  is a single commit with no parent: the app's source history on `main` and the
  served build are separate things, and an unreachable old build is garbage
  collected instead of piling up 39 MB of images in the repo forever.

  The build is done with --base-href /weed-flashcards/ because Pages serves a
  project site under /<repo>/, and web\flutter_bootstrap.js needs the matching
  prefix.

  Needs the GitHub CLI (gh) signed in, or at least a working git remote.

.EXAMPLE
  .\publish_web.ps1                    # build for /weed-flashcards/ and push
  .\publish_web.ps1 -NoBuild           # push whatever is in build\web right now
  .\publish_web.ps1 -BaseHref /weeds/  # a repo named "weeds"
#>
param(
    [string]$BaseHref = '/weed-flashcards/',
    [string]$Repo = 'origin',
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not $NoBuild) {
    & "$PSScriptRoot\build_web.ps1" -BaseHref $BaseHref
    if ($LASTEXITCODE -ne 0) { throw "build_web.ps1 failed" }
}

$out = Join-Path $PSScriptRoot 'build\web'
$index = Join-Path (Join-Path $PSScriptRoot '.git') 'gh-pages-index'

# The Pages branch gets its own README: it is the one GitHub shows when someone
# opens the repo looking for the app, so it talks about playing the game rather
# than about building it. site_readme.md in the source is where it is written.
$site = Join-Path $PSScriptRoot 'site_readme.md'
if (Test-Path $site) {
    Copy-Item $site (Join-Path $out 'README.md') -Force
    Write-Host "  site README: site_readme.md -> build\web\README.md"
}

# Turn build\web into a commit without touching the working tree or the real
# index: git plumbing with the work tree pointed at build\web and a scratch
# index file. `git add build\web\...` from the project root would have written
# the files under build/web/ inside the branch, and Pages would then serve the
# app at /weed-flashcards/build/web/ - a 404 for every asset.
$prevWorkTree = $env:GIT_WORK_TREE
$prevIndex = $env:GIT_INDEX_FILE
try {
    if (Test-Path $index) { Remove-Item $index -Force }
    $env:GIT_WORK_TREE = (Get-Item $out).FullName
    $env:GIT_INDEX_FILE = $index

    Push-Location $out
    try {
        git read-tree --empty
        if ($LASTEXITCODE -ne 0) { throw "git read-tree failed" }
        git add --force --all -- .
        if ($LASTEXITCODE -ne 0) { throw "git add failed" }
        $tree = (& git write-tree).Trim()
        if (-not $tree) { throw "git write-tree returned nothing" }
    } finally {
        Pop-Location
    }
} finally {
    $env:GIT_WORK_TREE = $prevWorkTree
    $env:GIT_INDEX_FILE = $prevIndex
    if (Test-Path $index) { Remove-Item $index -Force }
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$commit = (& git commit-tree $tree -m "web build $stamp").Trim()
if (-not $commit) { throw "git commit-tree failed" }
& git update-ref refs/heads/gh-pages $commit
if ($LASTEXITCODE -ne 0) { throw "git update-ref failed" }

Write-Host "gh-pages -> $commit" -ForegroundColor Cyan
& git push $Repo gh-pages --force
if ($LASTEXITCODE -ne 0) { throw "git push gh-pages failed" }

Write-Host "  Pages serves the branch a minute or two after the push." -ForegroundColor Green
Write-Host "  If the site has never been published, enable it once with:" -ForegroundColor Green
Write-Host "    gh api -X POST repos/<owner>/weed-flashcards/pages -f source[branch]=gh-pages -f source[path]=/"
