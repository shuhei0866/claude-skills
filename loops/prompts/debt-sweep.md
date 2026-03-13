# Debt Sweep (Item {{ITEM_INDEX}} / {{TOTAL_ITEMS}})

You are fixing a technical debt item from the project's backlog.

## Project

```
cd {{PROJECT_DIR}}
```

## Item to Fix

```json
{{ITEM}}
```

## Instructions

### Step 1: Analyze

Understand the item:
- Read the relevant file(s)
- Understand the context and why this item exists
- Determine if it's safe to fix without breaking other code
- Check what other code depends on or references the affected code

### Step 2: Fix (TDD)

Follow TDD to fix the item. The approach depends on the item type:

#### TODO/FIXME Comments
1. Read the comment and surrounding code to understand the original developer's intent
2. Write a test that captures the expected behavior after implementing the TODO/fix
3. Verify the test fails
4. Implement the change described by the comment
5. Remove the TODO/FIXME comment after the fix is complete
6. Verify the test passes

#### Lint Errors
1. Read the lint rule documentation to understand why the rule exists
2. Write a test that validates the correct behavior (if the lint error is in logic code)
3. Fix the lint violation properly -- **never suppress with eslint-disable or @ts-ignore**
4. If the rule is about code style (no logic change), no test is needed but verify lint passes
5. Verify the test passes (if applicable)

#### GitHub Issues
1. Read the full issue description, comments, and any linked PRs
2. Write tests that cover the requirements described in the issue
3. Verify the tests fail
4. Implement the solution following TDD
5. Verify the tests pass
6. Include `Fixes #<number>` or `Closes #<number>` in the commit message

#### Type Errors (TypeScript)
1. Understand why the type error exists (missing type, incorrect cast, `any` usage)
2. Write a test that exercises the code path with correct types
3. Replace `any` with proper types, add missing type definitions, or fix type mismatches
4. Never use `@ts-ignore` or `as any` to silence the error
5. Verify the project compiles cleanly with `npx tsc --noEmit`
6. Verify the test passes

### Step 3: Verify

After fixing:
1. Run the project's test suite (e.g., `pnpm test:run`, `pnpm check`)
2. Ensure no regressions
3. If any test fails that was passing before your change, **revert immediately**

### Step 4: Commit

Commit the fix as a single atomic commit:
- 1 item = 1 commit (do not batch multiple items in one commit)
- Use a descriptive commit message explaining what was fixed and why
- For GitHub Issues, include `Fixes #<number>` in the commit message

### Step 5: Report

Output the result:

```
<loop-result>{"status": "done", "summary": "Brief description of what was fixed"}</loop-result>
```

If you cannot fix the item (too risky, requires human decision, etc.):

```
<loop-result>{"status": "skip", "summary": "Reason for skipping"}</loop-result>
```

If the fix attempt failed (tests broke, build failed, etc.):

```
<loop-result>{"status": "fail", "summary": "What went wrong"}</loop-result>
```

## Safety Guards

- **Impact check**: Before applying a fix, verify it does not affect unrelated code paths
- **Revert on failure**: If tests fail after your fix, revert all changes immediately (`git checkout -- .`)
- **No cascading changes**: If fixing one item requires changing many unrelated files, skip it
- **1 item = 1 commit**: Each fix is atomic and independently revertable

## Skip Criteria

Skip an item (report `status: "skip"`) if any of the following apply:
- The fix requires a design decision that should involve a human
- The change would affect a public API contract
- The fix is a large refactor that cannot be safely scoped to a single commit
- The TODO/FIXME describes a known limitation that is intentionally deferred
- The lint rule is incorrect for this codebase (report this observation)
- The fix requires changes to database schemas or migrations
- The code is scheduled for removal or replacement (check git blame / recent PRs)
- You are not confident the fix is correct

## Rules

- Always use TDD: test first, then fix
- Don't make unrelated changes
- If unsure, skip rather than break things
- Revert your changes if the fix causes test failures
- Keep each fix minimal and focused
