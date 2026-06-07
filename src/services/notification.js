import { getLatestMetricsForAllServers, getAllServers } from '../database/schema.js';

const MAX_RETRIES = 3;
const RETRY_DELAY = 1000;

let cachedSettings = null;
let cacheExpiry = 0;
const CACHE_TTL = 60 * 1000;

async function fetchWithRetry(url, options, retries = MAX_RETRIES) {
  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch(url, options);
      if (response.ok) return response;
      
      if (i < retries - 1) {
        await new Promise(resolve => setTimeout(resolve, RETRY_DELAY));
      }
    } catch (e) {
      if (i < retries - 1) {
        await new Promise(resolve => setTimeout(resolve, RETRY_DELAY));
      } else {
        throw e;
      }
    }
  }
  throw new Error('Max retries exceeded');
}

async function loadNotificationSettings(db) {
  const now = Date.now();
  if (cachedSettings && now < cacheExpiry) {
    return cachedSettings;
  }

  const defaults = { tg_notify: 'false', tg_bot_token: '', tg_chat_id: '' };

  try {
    const row = await db.prepare(
      "SELECT value FROM settings WHERE key = 'site_options'"
    ).first();

    if (row) {
      try {
        const parsed = JSON.parse(row.value);
        const settings = {
          tg_notify: parsed.tg_notify || defaults.tg_notify,
          tg_bot_token: parsed.tg_bot_token || defaults.tg_bot_token,
          tg_chat_id: parsed.tg_chat_id || defaults.tg_chat_id
        };
        cachedSettings = settings;
        cacheExpiry = now + CACHE_TTL;
        return settings;
      } catch (e) {
        // JSON 解析失败，降级到独立 key
      }
    }
  } catch (e) {
    console.error('加载通知设置失败:', e);
  }

  cachedSettings = defaults;
  cacheExpiry = now + CACHE_TTL;
  return defaults;
}

export function clearNotificationSettingsCache() {
  cachedSettings = null;
  cacheExpiry = 0;
}

export async function sendTelegramNotification(settings, msg) {
  if (settings.tg_notify !== 'true' || !settings.tg_bot_token || !settings.tg_chat_id) return;
  
  try {
    await fetchWithRetry(`https://api.telegram.org/bot${settings.tg_bot_token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: settings.tg_chat_id,
        text: msg,
        parse_mode: 'Markdown'
      })
    });
  } catch (e) {
    console.error('Telegram 通知发送失败:', e);
  }
}

export async function sendWeworkNotification(settings, msg) {
  if (settings.tg_notify !== 'true' || !settings.tg_bot_token) return;

  try {
    await fetchWithRetry(settings.tg_bot_token, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        msgtype: "markdown",
        markdown: { content: msg }
      })
    });
  } catch (e) {
    console.error('企业微信通知发送失败:', e);
  }
}

export async function checkOfflineNodes(db) {
  const notifySettings = await loadNotificationSettings(db);
  if (notifySettings.tg_notify !== 'true') return;
  
  try {
    const allServers = await getAllServers(db);
    
    const latestMetricsMap = await getLatestMetricsForAllServers(db);
    
    let alertState = {};
    const stateRes = await db.prepare(
      "SELECT value FROM settings WHERE key = 'alert_state'"
    ).first();
    
    if (stateRes) {
      try {
        alertState = JSON.parse(stateRes.value);
      } catch (e) {
        alertState = {};
      }
    }

    let stateChanged = false;
    const now = Date.now();

    for (const s of allServers) {
      const latestMetrics = latestMetricsMap.get(s.id);
      
      let isOffline = true;
      if (latestMetrics) {
        const diff = now - latestMetrics.timestamp;
        isOffline = diff > 300000;
      }

      if (isOffline && !alertState[s.id]) {
        const msg = `⚠️ **节点离线告警**\n\n` +
          `**节点名称:** ${s.name}\n` +
          `**状态:** 离线 (超过5分钟未上报)\n` +
          `**时间:** ${new Date().toLocaleString('zh-CN', {timeZone: 'Asia/Shanghai'})}`;
        
        await sendTelegramNotification(notifySettings, msg);
        await sendWeworkNotification(notifySettings, msg);
        
        alertState[s.id] = true;
        stateChanged = true;
      } else if (!isOffline && alertState[s.id]) {
        const msg = `✅ **节点恢复通知**\n\n` +
          `**节点名称:** ${s.name}\n` +
          `**状态:** 恢复在线\n` +
          `**时间:** ${new Date().toLocaleString('zh-CN', {timeZone: 'Asia/Shanghai'})}`;
        
        await sendTelegramNotification(notifySettings, msg);
        await sendWeworkNotification(notifySettings, msg);
        
        delete alertState[s.id];
        stateChanged = true;
      }
    }

    if (stateChanged) {
      await db.prepare(
        'INSERT INTO settings (key, value) VALUES ("alert_state", ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value'
      ).bind(JSON.stringify(alertState)).run();
    }
  } catch (e) {
    console.error('离线检测失败:', e);
  }
}