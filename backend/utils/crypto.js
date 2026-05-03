const crypto = require('crypto');

function deriveEncryptionKey(hashedPassword, userId, username) {
    const saltInput = `${hashedPassword}|${userId}|${username}`;
    const salt = crypto.createHash('sha256').update(saltInput).digest();
    const key = crypto.pbkdf2Sync(
        hashedPassword,
        salt,
        100000,
        32,
        'sha256'
    );
    return key;
}

function encryptQRData(plaintext, hashedPassword, userId, username) {
    const encryptionKey = deriveEncryptionKey(hashedPassword, userId, username);
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey, iv);
    let encrypted = cipher.update(plaintext, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    const authTag = cipher.getAuthTag();
    return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;
}

function decryptQRData(ciphertext, hashedPassword, userId, username) {
    try {
        const encryptionKey = deriveEncryptionKey(hashedPassword, userId, username);
        const parts = ciphertext.split(':');
        if (parts.length !== 3) throw new Error('Format cipher tidak valid');
        const iv = Buffer.from(parts[0], 'hex');
        const authTag = Buffer.from(parts[1], 'hex');
        const encrypted = parts[2];
        const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey, iv);
        decipher.setAuthTag(authTag);
        let decrypted = decipher.update(encrypted, 'hex', 'utf8');
        decrypted += decipher.final('utf8');
        return decrypted;
    } catch (err) {
        console.error('[Decrypt] Error:', err.message);
        throw new Error('Gagal mendekripsi QR data');
    }
}

module.exports = { encryptQRData, decryptQRData };