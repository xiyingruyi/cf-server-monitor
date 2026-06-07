/**
 * 缓存管理模块
 * 集中管理所有内存缓存，包括：
 * - 服务器列表缓存
 * - 服务器详情缓存（统一替代 SELECT 1/id/*）
 * - 最新指标缓存
 * - 历史指标缓存
 */

const SERVERS_LIST_TTL = 60 * 1000;
let serversListCache = null;
let serversListCacheTime = 0;

const SERVER_DETAIL_TTL = 5 * 60 * 1000;
const serverDetailCache = new Map();

const LATEST_ALL_TTL = 30 * 1000;
let latestAllCache = null;
let latestAllCacheTime = 0;

const metricsHistoryCache = new Map();

export async function getAllServers(db, includeHidden = true) {
  const cacheKey = includeHidden ? 'all' : 'visible';
  const now = Date.now();
  
  if (serversListCache && serversListCache.cacheKey === cacheKey && now - serversListCache.time < SERVERS_LIST_TTL) {
    return serversListCache.data;
  }

  try {
    let query = 'SELECT * FROM servers ORDER BY sort_order ASC';
    if (!includeHidden) {
      query = "SELECT * FROM servers WHERE (is_hidden != '1' AND is_hidden != 1) ORDER BY sort_order ASC";
    }
    const { results } = await db.prepare(query).all();
    serversListCache = { data: results, time: now, cacheKey };
    return results;
  } catch (e) {
    console.error('获取服务器列表失败:', e);
    return serversListCache && serversListCache.cacheKey === cacheKey ? serversListCache.data : [];
  }
}

export function clearServersListCache() {
  serversListCache = null;
  serversListCacheTime = 0;
}

/**
 * 获取单个服务器详情（带缓存）
 * @param {object} db - 数据库实例
 * @param {string} id - 服务器 ID
 * @param {boolean} [includeHidden=false] - 是否包含隐藏服务器
 * @returns {object|null} 服务器对象，不存在返回 null
 */
export async function getServerDetail(db, id, includeHidden = false) {
  const now = Date.now();
  const cached = serverDetailCache.get(id);

  if (cached && now - cached.timestamp < SERVER_DETAIL_TTL) {
    const server = cached.data;
    if (!includeHidden && (server.is_hidden === '1' || server.is_hidden === 1)) {
      return null;
    }
    return server;
  }

  let query = 'SELECT * FROM servers WHERE id = ?';
  if (!includeHidden) {
    query += " AND (is_hidden != '1' AND is_hidden != 1)";
  }

  const server = await db.prepare(query).bind(id).first();

  if (server) {
    serverDetailCache.set(id, { data: server, timestamp: now });
  }

  return server;
}

/**
 * 检查服务器是否存在（复用服务器详情缓存）
 * @param {object} db - 数据库实例
 * @param {string} id - 服务器 ID
 * @returns {boolean} 服务器是否存在
 */
export async function checkServerExists(db, id) {
  const server = await getServerDetail(db, id, true);
  return !!server;
}

/**
 * 清除单个服务器的详情缓存
 * @param {string} id - 服务器 ID
 */
export function clearServerDetailCache(id) {
  serverDetailCache.delete(id);
}

/**
 * 获取最新指标缓存信息
 * @returns {object} 包含 cache、time、ttl 字段的对象
 */
export function getLatestMetricsCache() {
  return { cache: latestAllCache, time: latestAllCacheTime, ttl: LATEST_ALL_TTL };
}

export function setLatestMetricsCache(data) {
  latestAllCache = data;
  latestAllCacheTime = Date.now();
}

export function clearLatestMetricsCache() {
  latestAllCache = null;
  latestAllCacheTime = 0;
}

function getCacheKey(serverId, hours, columns) {
  const sortedColumns = columns.split(',').sort().join(',');
  return `${serverId}:${hours}:${sortedColumns}`;
}

export function getMetricsHistoryCache(serverId, hours, columns) {
  const key = getCacheKey(serverId, hours, columns);
  return metricsHistoryCache.get(key);
}

export function setMetricsHistoryCache(serverId, hours, columns, data) {
  const key = getCacheKey(serverId, hours, columns);
  metricsHistoryCache.set(key, { data, timestamp: Date.now() });
}

export function clearMetricsHistoryCache(serverId) {
  for (const key of metricsHistoryCache.keys()) {
    if (key.startsWith(`${serverId}:`)) {
      metricsHistoryCache.delete(key);
    }
  }
}

export function clearAllCaches() {
  clearServersListCache();
  serverDetailCache.clear();
  clearLatestMetricsCache();
  metricsHistoryCache.clear();
}