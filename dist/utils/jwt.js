"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.signAccessToken = signAccessToken;
exports.signRefreshToken = signRefreshToken;
exports.verifyAccessToken = verifyAccessToken;
exports.verifyRefreshToken = verifyRefreshToken;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const crypto_1 = require("crypto");
const env_1 = require("../config/env");
function signAccessToken(payload) {
    return jsonwebtoken_1.default.sign(payload, env_1.env.jwtSecret, { expiresIn: env_1.env.jwtExpiresIn });
}
function signRefreshToken(payload) {
    // jwtid keeps tokens unique: two logins in the same second would otherwise
    // produce identical tokens and hit the RefreshToken.token unique constraint.
    return jsonwebtoken_1.default.sign(payload, env_1.env.jwtRefreshSecret, { expiresIn: env_1.env.jwtRefreshExpiresIn, jwtid: (0, crypto_1.randomUUID)() });
}
function verifyAccessToken(token) {
    return jsonwebtoken_1.default.verify(token, env_1.env.jwtSecret);
}
function verifyRefreshToken(token) {
    return jsonwebtoken_1.default.verify(token, env_1.env.jwtRefreshSecret);
}
