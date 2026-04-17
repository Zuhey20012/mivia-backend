"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.calculateETA = calculateETA;
function calculateETA(distanceKm = 3) {
    const speedKmh = 25;
    const minutes = Math.max(5, Math.round((distanceKm / speedKmh) * 60));
    return { etaMinutes: minutes };
}
