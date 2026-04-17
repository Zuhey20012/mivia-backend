"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scoreCandidate = scoreCandidate;
function scoreCandidate(profileMatch = 0, behavior = 0, availability = 0, editorial = 0, distancePenalty = 0) {
    return 0.45 * profileMatch + 0.25 * behavior + 0.15 * availability + 0.10 * editorial - 0.05 * distancePenalty;
}
