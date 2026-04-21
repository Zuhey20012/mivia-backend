"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerUser = registerUser;
exports.loginUser = loginUser;
exports.refreshTokens = refreshTokens;
exports.logoutUser = logoutUser;
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const prisma_1 = require("../../lib/prisma");
const jwt_1 = require("../../utils/jwt");
async function registerUser(input) {
    const existing = await prisma_1.prisma.user.findUnique({ where: { email: input.email } });
    if (existing)
        throw new Error("Email already registered");
    const passwordHash = await bcryptjs_1.default.hash(input.password, 12);
    const user = await prisma_1.prisma.user.create({
        data: { name: input.name, email: input.email, phone: input.phone, passwordHash, role: input.role },
        select: { id: true, name: true, email: true, role: true, createdAt: true },
    });
    const tokens = generateTokens(user);
    await saveRefreshToken(user.id, tokens.refreshToken);
    return { user, ...tokens };
}
async function loginUser(input) {
    const user = await prisma_1.prisma.user.findUnique({ where: { email: input.email } });
    if (!user)
        throw new Error("Invalid credentials");
    const valid = await bcryptjs_1.default.compare(input.password, user.passwordHash);
    if (!valid)
        throw new Error("Invalid credentials");
    const safeUser = { id: user.id, name: user.name, email: user.email, role: user.role };
    const tokens = generateTokens(safeUser);
    await saveRefreshToken(user.id, tokens.refreshToken);
    return { user: safeUser, ...tokens };
}
async function refreshTokens(refreshToken) {
    const payload = (0, jwt_1.verifyRefreshToken)(refreshToken);
    const stored = await prisma_1.prisma.refreshToken.findUnique({ where: { token: refreshToken } });
    if (!stored || stored.expiresAt < new Date())
        throw new Error("Refresh token expired or invalid");
    await prisma_1.prisma.refreshToken.delete({ where: { token: refreshToken } });
    const user = await prisma_1.prisma.user.findUniqueOrThrow({
        where: { id: stored.userId },
        select: { id: true, name: true, email: true, role: true },
    });
    const tokens = generateTokens(user);
    await saveRefreshToken(user.id, tokens.refreshToken);
    return { user, ...tokens };
}
async function logoutUser(refreshToken) {
    await prisma_1.prisma.refreshToken.deleteMany({ where: { token: refreshToken } });
}
// ─── Helpers ────────────────────────────────────────────────────────────────
function generateTokens(user) {
    const accessToken = (0, jwt_1.signAccessToken)({ id: user.id, email: user.email, role: user.role });
    const refreshToken = (0, jwt_1.signRefreshToken)({ id: user.id });
    return { accessToken, refreshToken };
}
async function saveRefreshToken(userId, token) {
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
    await prisma_1.prisma.refreshToken.create({ data: { token, userId, expiresAt } });
}
