/**
 * Discrete Geohashing and Spatial Indexing Utility
 * Implements standard Base32 geohash encoding, decoding, 8-neighbor bounding calculation,
 * and spatial distance metrics for O(1) hyperlocal dispatch candidate lookups.
 */

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
const BITS = [16, 8, 4, 2, 1];

export interface BoundingBox {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

/**
 * Encode (latitude, longitude) to Base32 geohash string with specified precision.
 * Precision 5: ~4.9km x 4.9km
 * Precision 6: ~1.2km x 0.61km (Urban dispatch neighborhood)
 * Precision 7: ~153m x 153m (Hyperlocal proximity / doorstep arrival)
 */
export function encodeGeohash(latitude: number, longitude: number, precision: number = 6): string {
  let isEven = true;
  let latMin = -90, latMax = 90;
  let lngMin = -180, lngMax = 180;
  let bit = 0;
  let ch = 0;
  let geohash = "";

  while (geohash.length < precision) {
    if (isEven) {
      const mid = (lngMin + lngMax) / 2;
      if (longitude >= mid) {
        ch |= BITS[bit];
        lngMin = mid;
      } else {
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        ch |= BITS[bit];
        latMin = mid;
      } else {
        latMax = mid;
      }
    }

    isEven = !isEven;
    if (bit < 4) {
      bit++;
    } else {
      geohash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }

  return geohash;
}

/**
 * Decode geohash to bounding box coordinates.
 */
export function decodeBBox(geohash: string): BoundingBox {
  let isEven = true;
  let latMin = -90, latMax = 90;
  let lngMin = -180, lngMax = 180;

  for (let i = 0; i < geohash.length; i++) {
    const c = geohash[i];
    const cd = BASE32.indexOf(c);
    if (cd === -1) throw new Error(`Invalid geohash character: ${c}`);

    for (let j = 0; j < 5; j++) {
      const mask = BITS[j];
      if (isEven) {
        const mid = (lngMin + lngMax) / 2;
        if ((cd & mask) !== 0) {
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        const mid = (latMin + latMax) / 2;
        if ((cd & mask) !== 0) {
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      isEven = !isEven;
    }
  }

  return { minLat: latMin, maxLat: latMax, minLng: lngMin, maxLng: lngMax };
}

/**
 * Decode geohash to its center (latitude, longitude).
 */
export function decodeGeohash(geohash: string): { latitude: number; longitude: number } {
  const bbox = decodeBBox(geohash);
  return {
    latitude: (bbox.minLat + bbox.maxLat) / 2,
    longitude: (bbox.minLng + bbox.maxLng) / 2,
  };
}

/**
 * Neighbor directions in Base32 geohashing.
 */
const NEIGHBORS: Record<string, Record<string, string>> = {
  right: { even: "bc01fg45238967deuvhjyznpkmstqrwx", odd: "p0r21436x8zb9dcf5h7kjnmqesgutwvy" },
  left: { even: "238967debc01fg45kmstqrwxuvhjyznp", odd: "14365h7k9dcfesgutwvyp0r2x8zbkjnm" },
  top: { even: "p0r21436x8zb9dcf5h7kjnmqesgutwvy", odd: "bc01fg45238967deuvhjyznpkmstqrwx" },
  bottom: { even: "14365h7k9dcfesgutwvyp0r2x8zbkjnm", odd: "238967debc01fg45kmstqrwxuvhjyznp" },
};

const BORDERS: Record<string, Record<string, string>> = {
  right: { even: "bcfguvyz", odd: "prxz" },
  left: { even: "0145hjnp", odd: "028b" },
  top: { even: "prxz", odd: "bcfguvyz" },
  bottom: { even: "028b", odd: "0145hjnp" },
};

export function getAdjacent(hash: string, direction: "top" | "bottom" | "right" | "left"): string {
  const lowerHash = hash.toLowerCase();
  const lastChar = lowerHash.slice(-1);
  const type = lowerHash.length % 2 ? "odd" : "even";
  let parent = lowerHash.slice(0, -1);

  if (BORDERS[direction][type].indexOf(lastChar) !== -1 && parent.length > 0) {
    parent = getAdjacent(parent, direction);
  }

  const charIndex = NEIGHBORS[direction][type].indexOf(lastChar);
  if (charIndex === -1) return hash;
  return parent + BASE32[charIndex];
}

/**
 * Get the 8 adjacent neighbors of a geohash cell.
 * Returns array of 9 hashes (center + 8 surrounding cells) for O(1) contiguous search.
 */
export function getNeighbors(hash: string): string[] {
  const top = getAdjacent(hash, "top");
  const bottom = getAdjacent(hash, "bottom");
  const right = getAdjacent(hash, "right");
  const left = getAdjacent(hash, "left");

  const topRight = getAdjacent(top, "right");
  const topLeft = getAdjacent(top, "left");
  const bottomRight = getAdjacent(bottom, "right");
  const bottomLeft = getAdjacent(bottom, "left");

  return [hash, top, bottom, right, left, topRight, topLeft, bottomRight, bottomLeft];
}

/**
 * Accurate Haversine distance in meters between two lat/lng coordinates.
 */
export function distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000; // meters
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}
