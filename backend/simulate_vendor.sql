INSERT INTO "User" (email, name, password, role) VALUES ('bakery_test@example.com', 'Jane Doe', 'pass', 'VENDOR');
INSERT INTO "Store" (name, email, category, "isVerified", "ownerId", "commissionRate") 
SELECT 'The Artisan Bakery', 'bakery_test@example.com', 'HANDMADE', false, id, 15.0 FROM "User" WHERE email = 'bakery_test@example.com';
