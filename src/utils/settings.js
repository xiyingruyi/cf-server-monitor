const APPEARANCE_FIELDS = ['site_title', 'admin_title', 'custom_bg', 'custom_head', 'custom_script'];
const SITE_FIELDS = ['is_public', 'show_price', 'show_expire', 'show_bw', 'show_tf', 'tg_notify', 'tg_bot_token', 'tg_chat_id', 'turnstile_enabled', 'turnstile_site_key', 'turnstile_secret_key', 'jwt_secret', 'username', 'password'];

const defaults = {
  site_title: 'Cloudflare Server Monitor',
  admin_title: 'Admin Panel',
  custom_bg: '',
  custom_head: '',
  custom_script: '',
  is_public: 'true',
  show_price: 'true',
  show_expire: 'true',
  show_bw: 'true',
  show_tf: 'true',
  tg_notify: 'false',
  tg_bot_token: '',
  tg_chat_id: '',
  turnstile_enabled: 'false',
  turnstile_site_key: '',
  turnstile_secret_key: ''
};

function tryParseJSON(str) {
  if (!str) return null;
  try {
    return JSON.parse(str);
  } catch (e) {
    return null;
  }
}

export async function loadSettings(db) {
  const result = { ...defaults };
  let hasAppearance = false;
  let hasSite = false;

  try {
    // 1. 尝试从 appearance_options JSON 读取
    const appearanceRow = await db.prepare(
      "SELECT value FROM settings WHERE key = 'appearance_options'"
    ).first();
    if (appearanceRow) {
      const parsed = tryParseJSON(appearanceRow.value);
      if (parsed) {
        hasAppearance = true;
        for (const field of APPEARANCE_FIELDS) {
          if (parsed[field] !== undefined) {
            result[field] = parsed[field];
          }
        }
      }
    }

    // 2. 尝试从 site_options JSON 读取
    const siteRow = await db.prepare(
      "SELECT value FROM settings WHERE key = 'site_options'"
    ).first();
    if (siteRow) {
      const parsed = tryParseJSON(siteRow.value);
      if (parsed) {
        hasSite = true;
        for (const field of SITE_FIELDS) {
          if (parsed[field] !== undefined) {
            result[field] = parsed[field];
          }
        }
      }
    }

    // 3. 兼容旧格式：如果 JSON 字段未找到，回退读取旧独立 key
    if (!hasAppearance || !hasSite) {
      const { results } = await db.prepare('SELECT * FROM settings').all();
      if (results && results.length > 0) {
        results.forEach(r => {
          if (!hasAppearance && APPEARANCE_FIELDS.includes(r.key)) {
            result[r.key] = r.value;
          }
          if (!hasSite && SITE_FIELDS.includes(r.key)) {
            result[r.key] = r.value;
          }
        });
      }
    }
  } catch (e) {
    console.error('加载设置失败:', e);
  }

  return result;
}