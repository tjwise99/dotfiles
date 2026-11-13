---
name: link-pr
description: >-
  Record a pull request's ticket in its GitHub Development field, from a session with no browser.
  Needed whenever the PR's base is an integration or epic branch rather than the default one, where a
  `Closes #N` body keyword writes nothing and any gate reading the linked issue fails on the missing
  record. Carries the GraphQL mutation `gh` has no subcommand for, the node-id lookups it takes, and
  the read-back that distinguishes a working call from a silent no-op. Invoke straight after
  `gh pr create` on a non-default base.
---

# Link a PR to its ticket

**`Closes #N` in a PR body writes the Development-field record only when the base is the default
branch.** A sub-issue's PR targets its integration branch, so on every such PR the keyword writes
nothing while the body still reads as though it did.

That is what makes the failure expensive rather than obvious: the body looks right, and a process
gate that checks the PR's linked issue fails anyway. **Such a gate reads GitHub's recorded state**,
so no wording in the body will satisfy it. The requirement itself is the repo's — its
`CONTRIBUTING.md` or process ADR; this skill is the mechanism.

**This skill is advisory.** Nothing forces its use; the gate refuses the merge later, so an unlinked
PR is not lost, only expensive.

## Writing the record

There is a web UI for this — the **Development** panel on the pull request — and **no `gh`
subcommand**: nothing under `gh pr` writes it. `gh issue develop` is the near miss and is a different
thing, managing an issue's linked *branches* rather than a PR's closing reference, so it leaves the
gate exactly as red as it found it.

From a session without a browser the record is written with a GraphQL mutation, which takes **node
ids**, not numbers. Run from inside the repo, with `n` the issue number and `p` the PR number. In a
fork checkout `gh repo view` follows `gh repo set-default`, so check it names the repo the PR is on:

```sh
n=<issue>; p=<pr>
repo=(-f o="$(gh repo view --json owner --jq .owner.login)" -f r="$(gh repo view --json name --jq .name)")
issue=$(gh api graphql "${repo[@]}" -F n=$n \
  -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){id}}}' \
  --jq '.data.repository.issue.id')
pr=$(gh api graphql "${repo[@]}" -F p=$p \
  -f query='query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){id}}}' \
  --jq '.data.repository.pullRequest.id')
if [[ $issue == I_* && $pr == PR_* ]]; then
  gh api graphql -f i="$issue" -f pr="$pr" \
    -f query='mutation($i:ID!,$pr:ID!){addCloseIssueReferences(input:{issueId:$i,pullRequestIds:[$pr]}){clientMutationId}}'
else
  echo "lookup failed, not linking: issue=$issue pr=$pr" >&2
fi
```

A failed lookup leaves the error JSON in the variable rather than an empty string, so the guard tests
the node-id prefix, not emptiness.

For a ticket filed in another repository, run the issue lookup with `-f o=<owner> -f r=<name>` for
that repository in place of `"${repo[@]}"`.

**Read it back rather than trusting the exit code** — the mutation returns a null
`clientMutationId` on success, so a call that worked and a call that did nothing print the same
thing:

```sh
gh api graphql "${repo[@]}" -F p=$p \
  -f query='query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){closingIssuesReferences(first:5){nodes{number}}}}}' \
  --jq '.data.repository.pullRequest.closingIssuesReferences.nodes'
```

The ticket's number in that list is the whole of what the gate wants.

Undoing it is `removeCloseIssueReferences`, same input shape — the pair to reach for when a PR was
linked to the wrong ticket.

## When the mutation looks made up

It is not in `gh`'s help and both names are easy to doubt. They come from the live schema, and the
query that read them is how to check again if either is ever renamed:

```sh
gh api graphql -f query='{__type(name:"Mutation"){fields{name}}}' --jq '.data.__type.fields[].name' \
  | grep -i closeissue
```

## Project-specific obligations

Linking is one of several things a PR on a gated repo owes — branch shape, ticket labels and parent,
title format. Those are the repo's own `CONTRIBUTING.md`'s. Where a repo carries its own `link-pr`
skill, use that one there — it knows the repo's gate and docs.
