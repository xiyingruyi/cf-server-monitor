import { saveMetricsHistory } from '../database/schema.js';
import { checkServerExists, clearServerDetailCache } from '../utils/cache.js';

// 将最新一次上报打包成前端可直接消费的 "当前状态" 对象
// 与 /api/server 和 /api/servers 返回的字段保持一致，便于页面直接合并
function buildPayloadForBroadcast(id, metrics, extra = {}) {
  const ts = metrics.timestamp || Date.now();
  return {
    id,
    cpu: metrics.cpu ?? null,
    ram: metrics.ram ?? null,
    disk: metrics.disk ?? null,
    load_avg: metrics.load_avg ?? '0',
    net_in_speed: metrics.net_in_speed ?? null,
    net_out_speed: metrics.net_out_speed ?? null,
    net_rx: metrics.net_rx ?? null,
    net_tx: metrics.net_tx ?? null,
    processes: metrics.processes ?? null,
    tcp_conn: metrics.tcp_conn ?? null,
    udp_conn: metrics.udp_conn ?? null,
    ping_ct: metrics.ping_ct ?? null,
    ping_cu: metrics.ping_cu ?? null,
    ping_cm: metrics.ping_cm ?? null,
    ping_bd: metrics.ping_bd ?? null,
    ram_total: metrics.ram_total ?? null,
    ram_used: metrics.ram_used ?? null,
    swap_total: metrics.swap_total ?? null,
    swap_used: metrics.swap_used ?? null,
    disk_total: metrics.disk_total ?? null,
    disk_used: metrics.disk_used ?? null,
    cpu_cores: metrics.cpu_cores ?? null,
    cpu_info: metrics.cpu_info ?? '',
    arch: metrics.arch ?? '',
    os: metrics.os ?? '',
    country: metrics.country || extra.country || '',
    ip_v4: metrics.ip_v4 ?? '0',
    ip_v6: metrics.ip_v6 ?? '0',
    boot_time: metrics.boot_time ?? '',
    last_updated: ts,
    timestamp: ts
  };
}

// 内部辅助：向 Durable Object 发送广播
async function broadcastToDO(env, serverId, payload) {
  if (!env || !env.METRICS_BROADCASTER) return false;
  try {
    const id = env.METRICS_BROADCASTER.idFromName('global');
    const stub = env.METRICS_BROADCASTER.get(id);
    // 内部调用，不需要鉴权；即使失败也不影响 /update 返回
    await stub.fetch(`http://internal/push/${encodeURIComponent(serverId)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    return true;
  } catch (e) {
    // 广播失败不应该让客户端收到错误
    console.warn('[broadcast] DO push failed:', e.message || e);
    return false;
  }
}

export async function handleUpdate(request, env, ctx) {
  try {
    const data = await request.json();
    const { id, secret, metrics } = data;

    if (secret !== env.API_SECRET) {
      return new Response(JSON.stringify({ error: 'Unauthorized', code: 401 }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    let countryCode = request.cf?.country || '';
    if (countryCode.toUpperCase() === 'TW') countryCode = 'CN';

    const serverExists = await checkServerExists(env.DB, id);

    if (!serverExists) {
      return new Response('Server not found', { status: 404 });
    }

    await saveMetricsHistory(env.DB, id, metrics, countryCode);

    // 构建广播 payload 并异步触发 DO 推送（不阻塞响应）
    const payload = buildPayloadForBroadcast(id, metrics || {}, { country: countryCode });
    ctx.waitUntil(broadcastToDO(env, id, payload));

    return new Response('OK', { status: 200 });
  } catch (e) {
    console.error('更新数据失败:', e);
    return new Response(`Error: ${e.message}`, { status: 400 });
  }
}

// 暴露给 index.js 路由使用的 WebSocket 接入函数
export async function handleWebSocketUpgrade(request, env) {
  if (!env || !env.METRICS_BROADCASTER) {
    return new Response(JSON.stringify({ error: 'WebSocket not enabled', code: 503 }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  const url = new URL(request.url);
  // 透传 query 让 DO 读取 subscribe 参数
  const qs = url.search || '';
  try {
    const id = env.METRICS_BROADCASTER.idFromName('global');
    const stub = env.METRICS_BROADCASTER.get(id);
    return await stub.fetch(`http://internal/ws${qs}`, {
      method: request.method,
      headers: request.headers
    });
  } catch (e) {
    console.error('[ws] DO upgrade failed:', e);
    return new Response(JSON.stringify({ error: 'WebSocket error', code: 500 }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

export { clearServerDetailCache };
