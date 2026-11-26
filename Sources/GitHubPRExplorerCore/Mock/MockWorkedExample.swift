import Foundation

/// `acme/api #4826`, the pull request every Figma row shows. Every fact here is written by
/// hand to match the designs, because screenshots are compared with them.
enum MockWorkedExample {
    static let reference = PullRequestReference(repository: MockCast.api, number: 4826)

    static func make(now: Date) -> PullRequest {
        let id = "PR_mock_acme_api_4826"
        let sam = MockCast.samRivera, ada = MockCast.adaPark, jo = MockCast.joLindqvist, max = MockCast.maxChen
        let deployBot = MockCast.deployPreviewBot, coverageBot = MockCast.coverageBot
        func at(_ text: String) -> Date { MockWorld.date(text) }

        let files = [
            file("auth/session.ts", sessionPatch),
            file("auth/middleware.ts", middlewarePatch),
            file("auth/middleware.test.ts", middlewareTestPatch),
            file("api/routes/login.ts", loginPatch),
            file("docs/auth.md", docsPatch),
            file("api/routes/logout.ts", logoutPatch),
            file("api/routes/account.ts", accountPatch),
            file("api/server.ts", serverPatch),
            file("CHANGELOG.md", changelogPatch),
        ]

        let commitMessages: [(String, String)] = [
            ("Add loadSession and isNearExpiry to the session module", "2026-11-23T14:21:00Z"),
            ("Return the cookie from extendSession instead of writing it", "2026-11-23T14:38:00Z"),
            ("Refresh near-expiry sessions in authenticate", "2026-11-23T14:52:00Z"),
            ("Remove refreshSession calls from the login routes", "2026-11-23T15:05:00Z"),
            ("Test session refresh in the middleware", "2026-11-24T09:41:00Z"),
            ("Keep POST /login/refresh as a no-op for old web builds", "2026-11-24T09:58:00Z"),
            ("Run rate limiting after authentication", "2026-11-24T14:20:00Z"),
            ("Add refreshSessions option for routes that must not set cookies", "2026-11-24T14:41:00Z"),
            ("Report refreshes through onRefresh", "2026-11-25T09:14:00Z"),
            ("Add requireRecentSignIn for credential changes", "2026-11-25T12:30:00Z"),
            ("Update the auth docs and changelog", "2026-11-25T12:58:00Z"),
            ("Fix flaky expiry test by using the injected clock", "2026-11-25T17:36:00Z"),
        ]
        let commitIDs = [
            "3f1c9a2e7b4d6058c1e2a9f3b7d4c6e8a0f1b2c3", "8a2d4f6b1c3e5a7092d4f6b8c0e2a4c6e8f0a1b2",
            "c4e6a8b0d2f4a6c8e0b2d4f6a8c0e2b4d6f8a0c2", "1b3d5f7a9c1e3b5d7f9a1c3e5b7d9f1a3c5e7b9d",
            "e7f9a1b3c5d7e9f1a3b5c7d9e1f3a5b7c9d1e3f5", "5a7c9e1b3d5f7a9c1e3b5d7f9a1c3e5b7d9f1a3c",
            "9d1f3a5c7e9b1d3f5a7c9e1b3d5f7a9c1e3b5d7f", "2c4e6f8a0b2d4f6a8c0e2b4d6f8a0c2e4b6d8f0a",
            "6e8a0c2e4b6d8f0a2c4e6b8d0f2a4c6e8b0d2f4a", "0f2b4d6e8a0c2e4f6b8d0a2c4e6f8b0d2a4c6e8f",
            "7b9d1f3a5c7e9b1d3f5a7c9e1b3d5f7a9c1e3b5d", "d2f4a6c8e0b2d4f6a8c0e2b4d6f8a0c2e4b6d8f1",
        ]
        let commits = zip(commitMessages, commitIDs).map { pair, commitID in
            Commit(id: commitID, message: pair.0, author: sam, authoredAt: at(pair.1))
        }

        func check(_ name: String, required: Bool, _ start: String, _ end: String?, _ state: CheckState = .passed, failure: String? = nil) -> Check {
            Check(name: name, state: state, isRequired: required, startedAt: at(start), finishedAt: end.map(at), failureSummary: failure)
        }
        let checks = [
            check("lint", required: true, "2026-11-25T17:41:05Z", "2026-11-25T17:42:10Z"),
            check("typecheck", required: true, "2026-11-25T17:41:05Z", "2026-11-25T17:42:40Z"),
            check("unit-tests", required: true, "2026-11-25T17:41:10Z", "2026-11-25T17:44:55Z"),
            check("integration-tests", required: true, "2026-11-25T17:41:10Z", "2026-11-25T17:47:30Z"),
            check("e2e-chrome", required: true, "2026-11-25T17:41:30Z", "2026-11-25T17:47:42Z", .failed, failure: "2 tests failed"),
            check("e2e-firefox", required: false, "2026-11-25T17:41:30Z", "2026-11-25T17:48:05Z"),
            check("build-docker", required: true, "2026-11-25T17:56:00Z", nil, .running),
            check("migrations-check", required: false, "2026-11-25T17:41:05Z", "2026-11-25T17:41:52Z"),
            check("coverage", required: false, "2026-11-25T17:45:00Z", "2026-11-25T17:45:31Z"),
            check("codeql", required: false, "2026-11-25T17:41:20Z", "2026-11-25T17:45:48Z"),
            check("license-scan", required: false, "2026-11-25T17:41:05Z", "2026-11-25T17:41:33Z"),
            check("secret-scan", required: false, "2026-11-25T17:41:05Z", "2026-11-25T17:41:24Z"),
            check("openapi-diff", required: false, "2026-11-25T17:41:10Z", "2026-11-25T17:41:41Z"),
            check("deploy-preview", required: false, "2026-11-25T17:41:00Z", "2026-11-25T17:47:00Z"),
        ]

        let reviews = [
            Review(id: "\(id)_review_1", reviewer: ada, state: .approved, submittedAt: at("2026-11-25T16:00:00Z"),
                   body: "Approving the shape of this. One question on ordering with the rate limiter inline."),
            Review(id: "\(id)_review_2", reviewer: jo, state: .approved, submittedAt: at("2026-11-25T17:00:00Z"),
                   body: "Looks good. Left a note on the near-expiry window."),
        ]
        let reviewRequests = [
            ReviewRequest(reviewer: .team(MockCast.securityTeam), requestedAt: at("2026-11-23T15:14:00Z"), isCodeOwnerRequest: true),
        ]

        let threads = [
            ReviewThread(
                id: "\(id)_thread_1", path: "auth/middleware.ts", line: 112, side: .right,
                quotedLine: "        const refresh = await refreshSessionIfNearExpiry(req);",
                comments: [
                    ReviewComment(id: "\(id)_thread_1_comment_1", author: ada,
                                  body: "Does this refresh run before the rate limiter? If not, one request can be counted twice.",
                                  createdAt: at("2026-11-24T11:30:00Z")),
                    ReviewComment(id: "\(id)_thread_1_comment_2", author: sam,
                                  body: "It runs first now. `api/server.ts` mounts `authenticate` before `rateLimit`, so a refresh and the request it rides on count once.",
                                  createdAt: at("2026-11-24T15:00:00Z")),
                ]
            ),
            ReviewThread(
                id: "\(id)_thread_2", path: "auth/session.ts", line: 118, side: .right,
                quotedLine: "  return session.expiresAt.getTime() - now.getTime() < 5 * 60 * 1000;",
                comments: [
                    ReviewComment(id: "\(id)_thread_2_comment_1", author: jo,
                                  body: "Should near-expiry be a config value instead of 5 minutes hard-coded?",
                                  createdAt: at("2026-11-25T11:10:00Z")),
                ]
            ),
            ReviewThread(
                id: "\(id)_thread_3", path: "api/routes/login.ts", line: 27, side: .left,
                quotedLine: "      await refreshSession(req, res);",
                comments: [
                    ReviewComment(id: "\(id)_thread_3_comment_1", author: max,
                                  body: "Is removing this refresh safe for the single sign-on callback route?",
                                  createdAt: at("2026-11-25T17:20:00Z")),
                ]
            ),
        ]

        let previewURL = "https://pr-4826.api.preview.acme.example"
        var comments: [IssueComment] = []
        var builder = TimelineBuilder()
        func botComment(_ bot: Person, _ time: String, _ body: String) {
            comments.append(IssueComment(id: "\(id)_comment_\(comments.count + 1)", author: bot, body: body, createdAt: at(time)))
            builder.add(.commented, bot, at(time), "\(bot.login) commented")
        }
        func coverage(_ time: String, _ total: String, _ change: String) {
            botComment(coverageBot, time, "Coverage is **\(total)%** (\(change)%) on this branch.\n\n| Files changed | Lines covered |\n|---|---|\n| 9 | 91% |")
        }
        func deployed(_ time: String) {
            builder.add(.deployed, deployBot, at(time), "deploy-preview-bot deployed a preview to \(previewURL)")
        }

        // People: 14 events.
        builder.add(.opened, sam, at("2026-11-23T15:12:00Z"), "Sam Rivera opened this pull request")
        builder.add(.labelAdded, sam, at("2026-11-23T15:13:00Z"), "Sam Rivera added the auth and refactor labels")
        builder.add(.reviewRequested, sam, at("2026-11-23T15:14:00Z"), "Sam Rivera requested review from Ada Park, Jo Lindqvist and @acme/security")
        builder.add(.pushedCommits, sam, at("2026-11-24T10:02:00Z"), "Sam Rivera pushed 2 commits")
        builder.add(.commented, ada, at("2026-11-24T11:30:00Z"), "Ada Park commented on auth/middleware.ts")
        builder.add(.pushedCommits, sam, at("2026-11-24T14:45:00Z"), "Sam Rivera pushed 2 commits")
        builder.add(.commented, sam, at("2026-11-24T15:00:00Z"), "Sam Rivera commented on auth/middleware.ts")
        builder.add(.pushedCommits, sam, at("2026-11-25T09:20:00Z"), "Sam Rivera pushed 1 commit")
        builder.add(.commented, jo, at("2026-11-25T11:10:00Z"), "Jo Lindqvist commented on auth/session.ts")
        builder.add(.pushedCommits, sam, at("2026-11-25T13:05:00Z"), "Sam Rivera pushed 2 commits")
        builder.add(.reviewed, ada, at("2026-11-25T16:00:00Z"), "Ada Park approved these changes")
        builder.add(.reviewed, jo, at("2026-11-25T17:00:00Z"), "Jo Lindqvist approved these changes")
        builder.add(.commented, max, at("2026-11-25T17:20:00Z"), "Max Chen commented on api/routes/login.ts")
        builder.add(.pushedCommits, sam, at("2026-11-25T17:40:00Z"), "Sam Rivera pushed 1 commit")

        // Bots: 17 events, 9 from deploy-preview-bot and 8 from coverage-bot.
        deployed("2026-11-23T15:21:00Z")
        botComment(deployBot, "2026-11-23T15:21:30Z", "**Preview ready.** \(previewURL)\n\nThe preview is rebuilt on every push and removed when the pull request closes.")
        coverage("2026-11-23T15:24:00Z", "86.8", "+0.0")
        deployed("2026-11-24T10:09:00Z")
        coverage("2026-11-24T10:12:00Z", "86.1", "-0.7")
        builder.add(.labelAdded, coverageBot, at("2026-11-24T10:12:30Z"), "coverage-bot added the coverage-dropped label")
        deployed("2026-11-24T14:52:00Z")
        coverage("2026-11-24T14:55:00Z", "87.0", "+0.2")
        builder.add(.labelRemoved, coverageBot, at("2026-11-24T14:55:30Z"), "coverage-bot removed the coverage-dropped label")
        deployed("2026-11-25T09:27:00Z")
        botComment(deployBot, "2026-11-25T09:27:30Z", "**Preview updated** for 6e8a0c2. \(previewURL)")
        coverage("2026-11-25T09:30:00Z", "87.1", "+0.3")
        deployed("2026-11-25T13:12:00Z")
        coverage("2026-11-25T13:15:00Z", "87.2", "+0.4")
        deployed("2026-11-25T17:47:00Z")
        botComment(deployBot, "2026-11-25T17:47:30Z", "**Preview updated** for d2f4a6c. \(previewURL)")
        coverage("2026-11-25T17:50:00Z", "87.2", "+0.4")

        comments.sort { $0.createdAt < $1.createdAt }
        for index in comments.indices { comments[index].id = "\(id)_comment_\(index + 1)" }
        let timeline = builder.events(idPrefix: id)

        func ago(_ seconds: Int) -> Date { now.addingTimeInterval(-Double(seconds)) }
        let provenance = Provenance(
            metadata: SectionProvenance(source: .graphQLAPI, fetchedAt: ago(40)),
            checks: SectionProvenance(source: .restAPI, fetchedAt: ago(15)),
            reviews: SectionProvenance(source: .graphQLAPI, fetchedAt: ago(40)),
            files: SectionProvenance(source: .localClone, fetchedAt: ago(180)),
            threads: SectionProvenance(source: .graphQLAPI, fetchedAt: ago(40)),
            timeline: SectionProvenance(source: .push, fetchedAt: ago(10))
        )

        var pr = PullRequest(
            id: id,
            repository: MockCast.api,
            number: 4826,
            title: "Move session refresh into the auth middleware",
            body: body,
            author: sam,
            state: .open,
            isDraft: false,
            baseBranch: "main",
            headBranch: "session-refresh-middleware",
            headCommitID: commits[commits.count - 1].id,
            createdAt: at("2026-11-23T15:12:00Z"),
            updatedAt: timeline.last?.occurredAt ?? at("2026-11-25T17:50:00Z"),
            additions: files.reduce(0) { $0 + $1.additions },
            deletions: files.reduce(0) { $0 + $1.deletions },
            labels: [MockCast.label("auth"), MockCast.label("refactor")],
            milestone: Milestone(title: "2026.12", dueOn: at("2026-12-15T00:00:00Z")),
            linkedIssues: [LinkedIssue(repository: MockCast.api, number: 4710, title: "Sessions end while a user is active", isClosed: false)],
            assignees: [sam],
            mergeState: MergeState(mergeability: .mergeable, isBehindBase: false),
            reviewRequests: reviewRequests,
            reviews: reviews,
            reviewDecision: .reviewRequired,
            codeOwners: CodeOwners.matches(rules: MockCast.codeOwnerRules(for: MockCast.api), paths: files.map(\.path)),
            checks: checks,
            files: files,
            commits: commits,
            reviewThreads: threads,
            comments: comments,
            timeline: timeline,
            provenance: provenance
        )
        pr.mergeState.blockedReasons = MockPullRequestFactory.blockedReasons(pr, profile: MockVocabulary.api)
        return pr
    }

    private static func file(_ path: String, _ hunks: [PatchWriter.Hunk]) -> ChangedFile {
        let patch = PatchWriter.write(hunks)
        let lines = hunks.flatMap(\.lines)
        return ChangedFile(path: path, changeKind: .modified,
                           additions: lines.count { $0.hasPrefix("+") },
                           deletions: lines.count { $0.hasPrefix("-") },
                           patch: patch)
    }

    static let body = """
        Session refresh lives in each route handler today, and three handlers forgot to call it, so people on those pages are signed out while they are working. This moves the refresh into the auth middleware, so every request that passes `authenticate` extends a session with less than five minutes left. The session module no longer touches the response: `extendSession` returns the cookie and the middleware writes it. `POST /login/refresh` stays as a no-op so older web app builds keep working. Rate limiting now runs after authentication, so limits can be keyed by user.

        - [x] Move the refresh into `authenticate`
        - [x] Remove the calls from the route handlers
        - [x] Tests for refresh, no refresh, and the opt-out
        - [ ] Check the single sign-on callback on staging
        """

    // MARK: Patches

    // auth/session.ts: +64 −31. Jo's thread is on new line 118.
    static let sessionPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 1, text: #"""
             import { randomUUID } from 'node:crypto';
            -import type { Request, Response } from 'express';
            +import type { Request } from 'express';
             import { db } from '../db';
             import { logger } from '../lib/logger';
            +import { clock } from '../lib/clock';
            +import type { SessionRecord, SessionRefresh } from './types';

             const SESSION_COOKIE = 'acme_session';
             const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
            """#),
        PatchWriter.Hunk(oldStart: 91, section: "export function readSessionId(req: Request): string | null {", text: #"""
               return match ? decodeURIComponent(match[1]) : null;
             }

            -export async function refreshSession(req: Request, res: Response): Promise<void> {
            -  const sessionId = readSessionId(req);
            -  if (!sessionId) {
            -    return;
            -  }
            -
            -  const session = await db.sessions.findById(sessionId);
            -  if (!session) {
            -    res.clearCookie(SESSION_COOKIE);
            -    return;
            -  }
            -
            -  const remaining = session.expiresAt.getTime() - Date.now();
            -  if (remaining > 5 * 60 * 1000) {
            -    return;
            -  }
            -
            -  session.expiresAt = new Date(Date.now() + SESSION_TTL_MS);
            -  await db.sessions.update(session.id, { expiresAt: session.expiresAt });
            -  res.cookie(SESSION_COOKIE, session.id, {
            -    httpOnly: true,
            -    secure: true,
            -    sameSite: 'lax',
            -    expires: session.expiresAt,
            -  });
            -  logger.debug('session refreshed', { sessionId: session.id });
            -}
            +/**
            + * Loads the session named by the request's cookie, if there is one.
            + * Returns null when the cookie is missing or the session has ended.
            + */
            +export async function loadSession(req: Request): Promise<SessionRecord | null> {
            +  const sessionId = readSessionId(req);
            +  if (!sessionId) {
            +    return null;
            +  }
            +
            +  const session = await db.sessions.findById(sessionId);
            +  if (!session || session.revokedAt) {
            +    return null;
            +  }
            +  return session;
            +}
            +
            +/**
            + * True when the session ends within the near-expiry window, so the
            + * middleware should extend it before handling the request.
            + */
            +export function isNearExpiry(session: SessionRecord, now = clock.now()): boolean {
            +  return session.expiresAt.getTime() - now.getTime() < 5 * 60 * 1000;
            +}
            +
            +/**
            + * Extends a session by the full lifetime and saves it. The caller writes
            + * the cookie, so this module never touches the response object.
            + */
            +export async function extendSession(session: SessionRecord): Promise<SessionRefresh> {
            +  const expiresAt = new Date(clock.now().getTime() + SESSION_TTL_MS);
            +  await db.sessions.update(session.id, { expiresAt });
            +  logger.debug('session extended', { sessionId: session.id });
            +  return {
            +    sessionId: session.id,
            +    expiresAt,
            +    cookie: {
            +      name: SESSION_COOKIE,
            +      value: session.id,
            +      options: {
            +        httpOnly: true,
            +        secure: true,
            +        sameSite: 'lax',
            +        expires: expiresAt,
            +      },
            +    },
            +  };
            +}
            +
            +export async function refreshSessionIfNearExpiry(req: Request): Promise<SessionRefresh | null> {
            +  const session = await loadSession(req);
            +  if (!session || !isNearExpiry(session)) {
            +    return null;
            +  }
            +  return extendSession(session);
            +}

             export async function revokeSession(sessionId: string): Promise<void> {
               await db.sessions.update(sessionId, { revokedAt: new Date() });
            """#),
        PatchWriter.Hunk(oldStart: 140, section: "export async function revokeAllSessions(userId: string): Promise<number> {", text: #"""
               const sessions = await db.sessions.findActiveByUser(userId);
               for (const session of sessions) {
            -    await db.sessions.update(session.id, { revokedAt: new Date() });
            -    logger.info('session revoked', { sessionId: session.id });
            +    await db.sessions.update(session.id, { revokedAt: clock.now() });
            +    logger.info('session revoked', { sessionId: session.id, userId });
               }
            -  return sessions.length;
            +  const count = sessions.length;
            +  logger.info('sessions revoked for user', { userId, count });
            +  return count;
             }
            """#),
    ]

    // auth/middleware.ts: +48 −12. Ada's thread is on new line 112.
    static let middlewarePatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 1, text: #"""
             import type { NextFunction, Request, Response } from 'express';
            -import { loadSessionUser } from './session';
            +import { loadSession, refreshSessionIfNearExpiry } from './session';
            +import type { SessionRefresh } from './types';
             import { HttpError } from '../lib/errors';
             import { logger } from '../lib/logger';
            +import { metrics } from '../lib/metrics';

             export interface AuthOptions {
               /** Routes that do not need a signed-in user. */
               publicPaths: string[];
            +  /**
            +   * Extend sessions that are close to ending. On by default. Turn it off
            +   * for routes that must not set cookies, such as the health check.
            +   */
            +  refreshSessions?: boolean;
            +  onRefresh?: (refresh: SessionRefresh) => void;
             }

             export function isPublicPath(path: string, options: AuthOptions): boolean {
            """#),
        PatchWriter.Hunk(oldStart: 94, section: "export function authenticate(options: AuthOptions) {", text: #"""
                   return next();
                 }

            -    const user = await loadSessionUser(req);
            -    if (!user) {
            -      return next(new HttpError(401, 'sign in required'));
            -    }
            -
            -    req.user = user;
            -    next();
            +    try {
            +      const session = await loadSession(req);
            +      if (!session) {
            +        return next(new HttpError(401, 'sign in required'));
            +      }
            +
            +      if (options.refreshSessions !== false) {
            +        const refresh = await refreshSessionIfNearExpiry(req);
            +        if (refresh) {
            +          res.cookie(refresh.cookie.name, refresh.cookie.value, refresh.cookie.options);
            +          metrics.increment('auth.session.refreshed');
            +          options.onRefresh?.(refresh);
            +        }
            +      }
            +
            +      req.session = session;
            +      req.user = await session.user();
            +      next();
            +    } catch (error) {
            +      logger.error('authentication failed', { error, path: req.path });
            +      next(error);
            +    }
               };
             }

            """#),
        PatchWriter.Hunk(oldStart: 128, section: "export function authenticate(options: AuthOptions) {", text: #"""
             /** Like `authenticate`, but lets anonymous requests through. */
             export function optionalAuth(_options: AuthOptions) {
               return async (req: Request, _res: Response, next: NextFunction) => {
            -    const user = await loadSessionUser(req);
            -    if (user) {
            -      req.user = user;
            +    const session = await loadSession(req);
            +    if (session) {
            +      req.session = session;
            +      req.user = await session.user();
                 }
            -    next();
            +    return next();
               };
             }
            +
            +/**
            + * Rejects requests whose session was refreshed more than `maxAgeMs` ago.
            + */
            +export function requireRecentSignIn(maxAgeMs: number) {
            +  return (req: Request, _res: Response, next: NextFunction) => {
            +    if (Date.now() - (req.session?.signedInAt?.getTime() ?? 0) > maxAgeMs) {
            +      return next(new HttpError(403, 'sign in again to continue'));
            +    }
            +    return next();
            +  };
            +}
            """#),
    ]

    // auth/middleware.test.ts: +71 −4.
    static let middlewareTestPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 1, text: #"""
             import { describe, expect, it, vi } from 'vitest';
            -import { authenticate } from './middleware';
            +import { authenticate, requireRecentSignIn } from './middleware';
            +import * as session from './session';
            +import { fakeSession } from '../test/fakes';
             import { makeRequest, makeResponse } from '../test/http';

             describe('authenticate', () => {
            """#),
        PatchWriter.Hunk(oldStart: 24, section: "describe('authenticate', () => {", text: #"""
               it('rejects requests without a session', async () => {
                 const next = vi.fn();
            -    const req = makeRequest({ path: '/account' });
            -    await authenticate({ publicPaths: [] })(req, makeResponse(), next);
            -    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 401 }));
            +    const req = makeRequest({ path: '/account', cookies: {} });
            +    const res = makeResponse();
            +    await authenticate({ publicPaths: [] })(req, res, next);
            +    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 401 }));
            +    expect(res.cookie).not.toHaveBeenCalled();
               });
             });
            +
            +describe('session refresh in authenticate', () => {
            +  const publicPaths: string[] = [];
            +
            +  it('extends a session that is close to ending', async () => {
            +    const current = fakeSession({ expiresInMs: 2 * 60 * 1000 });
            +    vi.spyOn(session, 'loadSession').mockResolvedValue(current);
            +    const req = makeRequest({ path: '/account', cookies: { acme_session: current.id } });
            +    const res = makeResponse();
            +    const next = vi.fn();
            +
            +    await authenticate({ publicPaths })(req, res, next);
            +
            +    expect(res.cookie).toHaveBeenCalledWith('acme_session', current.id, expect.any(Object));
            +    expect(next).toHaveBeenCalledWith();
            +  });
            +
            +  it('leaves a fresh session alone', async () => {
            +    const current = fakeSession({ expiresInMs: 60 * 60 * 1000 });
            +    vi.spyOn(session, 'loadSession').mockResolvedValue(current);
            +    const req = makeRequest({ path: '/account', cookies: { acme_session: current.id } });
            +    const res = makeResponse();
            +
            +    await authenticate({ publicPaths })(req, res, vi.fn());
            +
            +    expect(res.cookie).not.toHaveBeenCalled();
            +  });
            +
            +  it('does not refresh when refreshSessions is false', async () => {
            +    const current = fakeSession({ expiresInMs: 30 * 1000 });
            +    vi.spyOn(session, 'loadSession').mockResolvedValue(current);
            +    const req = makeRequest({ path: '/health', cookies: { acme_session: current.id } });
            +    const res = makeResponse();
            +
            +    await authenticate({ publicPaths, refreshSessions: false })(req, res, vi.fn());
            +
            +    expect(res.cookie).not.toHaveBeenCalled();
            +  });
            +
            +  it('reports each refresh to onRefresh', async () => {
            +    const current = fakeSession({ expiresInMs: 60 * 1000 });
            +    vi.spyOn(session, 'loadSession').mockResolvedValue(current);
            +    const onRefresh = vi.fn();
            +    const req = makeRequest({ path: '/account', cookies: { acme_session: current.id } });
            +
            +    await authenticate({ publicPaths, onRefresh })(req, makeResponse(), vi.fn());
            +
            +    expect(onRefresh).toHaveBeenCalledWith(expect.objectContaining({ sessionId: current.id }));
            +  });
            +});
            +
            +describe('requireRecentSignIn', () => {
            +  it('asks for a new sign-in after the limit', () => {
            +    const next = vi.fn();
            +    const req = makeRequest({ path: '/account/password' });
            +    req.session = fakeSession({ signedInMsAgo: 20 * 60 * 1000 });
            +
            +    requireRecentSignIn(10 * 60 * 1000)(req, makeResponse(), next);
            +
            +    expect(next).toHaveBeenCalledWith(expect.objectContaining({ status: 403 }));
            +    expect(next).toHaveBeenCalledTimes(1);
            +  });
            +});
            """#),
    ]

    // api/routes/login.ts: +9 −28. Max's thread is on old line 27, a removed line.
    static let loginPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 1, text: #"""
             import { Router } from 'express';
            -import { refreshSession } from '../../auth/session';
            -import { loadSessionUser } from '../../auth/session';
            +import { authenticate } from '../../auth/middleware';
             import { signIn, signOut, completeSingleSignOn } from '../../auth/sign-in';
             import { HttpError } from '../../lib/errors';

             export const loginRoutes = Router();
            +loginRoutes.use(authenticate({ publicPaths: ['/login', '/login/sso/callback'] }));

            """#),
        PatchWriter.Hunk(oldStart: 20, section: "loginRoutes.get('/login/sso/callback', async (req, res, next) => {", text: #"""
                 const result = await completeSingleSignOn(req.query);
                 res.cookie('acme_session', result.sessionId, result.cookieOptions);

            -    // The callback sets a new cookie, so refresh it straight away
            -    // to give it the full lifetime instead of the provider's default.
            -    const user = await loadSessionUser(req);
            -    if (user) {
            -      await refreshSession(req, res);
            -    }
            -
                 res.redirect(result.returnTo ?? '/');
               } catch (error) {
                 next(error);
            """#),
        PatchWriter.Hunk(oldStart: 48, section: "loginRoutes.post('/logout', async (req, res, next) => {", text: #"""
                 next(error);
               }
             });
            -
            -// Called by the web app every few minutes to keep the session alive.
            -loginRoutes.post('/login/refresh', async (req, res, next) => {
            -  try {
            -    const user = await loadSessionUser(req);
            -    if (!user) {
            -      throw new HttpError(401, 'sign in required');
            -    }
            -    await refreshSession(req, res);
            -    res.status(204).end();
            -  } catch (error) {
            -    next(error);
            -  }
            -});
            +
            +// Sessions are now extended by the auth middleware on every request, so
            +// the web app no longer needs to call a refresh route.
            +loginRoutes.post('/login/refresh', (_req, res) => {
            +  res.status(204).end();
            +});

             loginRoutes.get('/me', async (req, res, next) => {
               try {
            -    const user = await loadSessionUser(req);
            -    if (!user) {
            -      throw new HttpError(401, 'sign in required');
            -    }
            -    await refreshSession(req, res);
            +    const user = req.user;
                 res.json({ id: user.id, email: user.email, name: user.name });
               } catch (error) {
                 next(error);
            """#),
    ]

    // docs/auth.md: +12 −3.
    static let docsPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 40, section: "Sessions and cookies", text: #"""
             ## Session lifetime

             Sessions last 12 hours from sign-in.
            -Each route that needs a signed-in user calls `refreshSession` itself, which
            -extends the session when it has less than 5 minutes left.
            -The web app also calls `POST /login/refresh` every few minutes.
            +The auth middleware extends a session when it has less than 5 minutes left,
            +on every request that passes through `authenticate`. Route handlers no longer
            +call `refreshSession` themselves.
            +
            +To skip the refresh on a route that must not set cookies, pass
            +`refreshSessions: false`:
            +
            +```ts
            +router.use(authenticate({ publicPaths: [], refreshSessions: false }));
            +```
            +
            +`POST /login/refresh` still answers 204 for older web app builds, and does nothing.

             ## Signing out

            """#),
    ]

    // api/routes/logout.ts: +2 −4.
    static let logoutPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 1, text: #"""
             import { Router } from 'express';
            -import { refreshSession, revokeSession } from '../../auth/session';
            +import { revokeSession } from '../../auth/session';

             export const logoutRoutes = Router();

            """#),
        PatchWriter.Hunk(oldStart: 14, section: "logoutRoutes.post('/logout', async (req, res, next) => {", text: #"""
             logoutRoutes.post('/logout', async (req, res, next) => {
               try {
            -    await refreshSession(req, res);
            -    const sessionId = req.cookies.acme_session;
            -    await revokeSession(sessionId);
            +    await revokeSession(req.session.id);
                 res.clearCookie('acme_session');
                 res.status(204).end();
               } catch (error) {
            """#),
    ]

    // api/routes/account.ts: +2 −3.
    static let accountPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 1, text: #"""
             import { Router } from 'express';
            -import { refreshSession } from '../../auth/session';
             import { accounts } from '../../db/accounts';
            +import { requireRecentSignIn } from '../../auth/middleware';

             export const accountRoutes = Router();
            """#),
        PatchWriter.Hunk(oldStart: 18, section: "accountRoutes.get('/account', async (req, res, next) => {", text: #"""
             accountRoutes.get('/account', async (req, res, next) => {
               try {
            -    await refreshSession(req, res);
            -    const account = await accounts.findByUser(req.user.id);
            +    const account = await accounts.findByUser(req.user.id, { include: ['plan'] });
                 res.json(account);
               } catch (error) {
            """#),
    ]

    // api/server.ts: +3 −2.
    static let serverPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 12, section: "export function createServer(config: ServerConfig) {", text: #"""
               const app = express();
               app.use(express.json());
               app.use(cookieParser());
            -  app.use(rateLimit(config.rateLimit));
            -  app.use(authenticate({ publicPaths: config.publicPaths }));
            +  app.use(authenticate({ publicPaths: config.publicPaths, refreshSessions: true }));
            +  // Rate limiting runs after auth so limits can be keyed by user.
            +  app.use(rateLimit(config.rateLimit));

               app.use('/', loginRoutes);
               app.use('/', logoutRoutes);
            """#),
    ]

    // CHANGELOG.md: +1 −0.
    static let changelogPatch: [PatchWriter.Hunk] = [
        PatchWriter.Hunk(oldStart: 1, text: #"""
             # Changelog

             ## Unreleased

            +- Sessions are extended by the auth middleware instead of each route handler.
             - Webhook deliveries retry up to five times.
            """#),
    ]
}
