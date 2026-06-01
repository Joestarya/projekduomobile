const { encryptQRData, decryptQRData } = require('../utils/crypto');
const { ensureQrDataColumn } = require('../schemas/usersSchema');
const {
    getUserByIdWithQr,
    getUserByUsernameOrFullName,
    getUserByUsernameWithQr,
    updateUserQrData,
} = require('../models/userModel');

const scanQr = async (req, res) => {
    const { user_id, username, full_name, qr_data } = req.body;

    if ((!user_id || String(user_id).trim() === '') && (!username || username.trim() === '') && (!full_name || full_name.trim() === '')) {
        return res.status(400).json({ message: 'Identitas user tidak boleh kosong' });
    }
    if (!qr_data || qr_data.trim() === '') {
        return res.status(400).json({ message: 'Data QR tidak boleh kosong' });
    }

    try {
        await ensureQrDataColumn();

        const parsedId = user_id ? parseInt(String(user_id), 10) : NaN;
        let user = null;

        if (!isNaN(parsedId) && parsedId > 0) {
            user = await getUserByIdWithQr(parsedId);
        } else {
            const nameA = username || full_name;
            const nameB = full_name || username;
            user = await getUserByUsernameOrFullName(nameA, nameB);
        }

        if (!user) return res.status(404).json({ message: 'User tidak ditemukan' });

        let encryptedQRData;
        try {
            encryptedQRData = encryptQRData(qr_data, user.password, user.id, user.username);
        } catch (err) {
            return res.status(500).json({ error: 'Gagal enkripsi QR data', detail: err.message });
        }

        await updateUserQrData(user.id, encryptedQRData);
        return res.status(200).json({
            message: 'Data QR berhasil disimpan (encrypted dengan PBKDF2)',
            user_id: user.id,
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

const getQrData = async (req, res) => {
    const { user_id, username } = req.query;

    if ((!user_id || String(user_id).trim() === '') && (!username || username.trim() === '')) {
        return res.status(400).json({ message: 'user_id atau username harus dikirimkan' });
    }

    try {
        await ensureQrDataColumn();

        let user = null;
        if (user_id) {
            const parsedId = parseInt(String(user_id), 10);
            if (isNaN(parsedId)) return res.status(400).json({ message: 'user_id harus berupa angka' });
            user = await getUserByIdWithQr(parsedId);
        } else {
            user = await getUserByUsernameWithQr(username);
        }

        if (!user) return res.status(404).json({ message: 'User tidak ditemukan' });

        let decryptedQRData = null;
        if (user.qr_data) {
            try {
                decryptedQRData = decryptQRData(user.qr_data, user.password, user.id, user.username);
            } catch (err) {
                return res.status(500).json({ error: 'Gagal dekripsi QR data', detail: err.message });
            }
        }

        return res.json({ id: user.id, username: user.username, full_name: user.full_name, qr_data: decryptedQRData });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

module.exports = {
    scanQr,
    getQrData,
};
