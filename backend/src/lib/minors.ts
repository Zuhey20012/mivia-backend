import { prisma } from "./prisma";

/**
 * Under-18 rule (DSA Art. 28; docs/design/category-sections-v2.md §2): no profiling-based recommendations or ads for
 * users known or likely to be under 18. Malvoya has no personalised ranking today (the feed uses freshness, engagement,
 * distance and rating only, see drops RANKING_EXPLANATION); any future personalisation must check this first.
 * "Known or likely": User.isMinor, set by an admin (PATCH /admin/users/:id/minor) or by a future age signal.
 */
export async function mayPersonalise(viewer: { id: number } | null | undefined): Promise<boolean> {
  if (!viewer) return false; // nothing to personalise for signed-out viewers
  const u = await prisma.user.findUnique({ where: { id: viewer.id }, select: { isMinor: true } });
  return !!u && !u.isMinor;
}
