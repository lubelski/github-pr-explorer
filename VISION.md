# Vision

> Draft, written on 2026-11-25 from the owner's first description of the idea.
> The owner has not approved it yet.
> There is no history to mine, so each line traces to something the owner said, not to merged work.

`github-pr-explorer` exists so that finding, reading, and deciding on a pull request never waits on a web page.
It serves people and teams who spend their day in GitHub pull requests.
It owns exactly one thing: a copy of the pull requests you care about, kept current on this Mac, and a native page for each one that the team arranges for itself.

## The local index is what you look at

Every screen reads from the index on this Mac.
Opening, searching, filtering, and moving between pull requests do not touch the network.
The network belongs to the sync layer and to nothing else.
GitHub is the truth, and the index is a copy that can be deleted and rebuilt.

## Sync takes the fastest honest source

Any source is fair: GitHub's APIs, `gh`, a local clone, push, or the web page itself.
A fact comes from wherever it arrives soonest and cheapest.
Every fact carries where it came from and how old it is, and the page shows its age when the age matters.
The app may show what it expects to be true before GitHub confirms it.
When it does, it says so.
When GitHub disagrees, GitHub wins and the person is told.
Nothing a person did is dropped silently.

## A page is an arrangement of blocks

Every part of a pull request is a block.
No block has a fixed place.
A team arranges its page by moving the blocks on the page itself, not by filling in a settings form.
A layout is data that can be named, copied, and shared.
A new kind of information arrives as a new block, not as a new fixed region.

## Rules choose the layout, and a rule is a filter

Which layout a pull request gets is decided by rules the team writes.
A rule is a filter over the index, plus a layout.
There is one filter language, and search, saved views, and layout rules all use it.
Anything the index knows can be filtered on, down to the reviewer, the file tree touched, and the code owner.
The app can always say which rule matched a pull request and why.

## The page shows what was asked for

A page shows what its layout puts there and nothing else.
The layouts that ship leave out what most reviewers skip.
What is left out is one step away, and never gone.

## The review finishes here

A person can read, comment, approve, and merge without opening a browser.
Everything a person decides is written to GitHub, so teammates on the web page see the same pull request.

## What it is not

It is not a notifier: being told about a change follows from the index, and is not the product.
It is not a git client or an editor, and it does not make commits.
It is not a replacement for GitHub, and it keeps no review state that GitHub does not have.
It is not a CI system or a merge queue.
It is not a wrapper around GitHub's web page.

## The tests

A change aligns when it makes a pull request faster to find, read, or decide on from the index, or gives a team more say over what its page shows.

A change should be resisted when it makes a screen wait on the network, gives a block a place the team cannot change, adds a second way to write a filter, hides how old or how certain a fact is, or keeps review state that GitHub does not have.
