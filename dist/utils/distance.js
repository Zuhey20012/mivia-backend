"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.haversineKm = haversineKm;
exports.calcEtaMinutes = calcEtaMinutes;
/**
 * Haversine formula — distance between two lat/lng points in km.
 */
function haversineKm(lat1, lng1, lat2, lng2) {
    const R = 6371;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a = Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLng / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
function toRad(deg) { return (deg * Math.PI) / 180; }
/**
 * ETA in minutes: distance / avg speed + packaging buffer.
 * Clamped between 20 and 120 minutes.
 */
function calcEtaMinutes(distanceKm) {
    const avgSpeedKmh = 25; // city courier speed
    const packagingMins = 10;
    const travelMins = (distanceKm / avgSpeedKmh) * 60;
    return Math.min(120, Math.max(20, Math.round(travelMins + packagingMins)));
}
