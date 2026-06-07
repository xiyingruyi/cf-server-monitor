const API_BASE = window.location.origin
const WS_PROTO = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
const WS_BASE = `${WS_PROTO}//${window.location.host}`

// -------------------------------------------------------------------------
// WebSocket 实时推送客户端
//   createLiveSocket(subscribe, { onUpdate, onStatus, onMessage })
//   subscribe = 'all'            -> 订阅所有服务器（首页）
//   subscribe = <serverId>       -> 只订阅某台服务器（详情页）
//
//   onUpdate({ serverId, data }): 收到最新一次指标时调用
//   onStatus({ connected, reason }): 连接状态变化时调用
//
//   返回值：{ close(), reconnect() }
// -------------------------------------------------------------------------
export const createLiveSocket = (subscribe, handlers = {}) => {
  const { onUpdate, onStatus, onMessage } = handlers
  const scope = (subscribe || 'all').toLowerCase()
  let ws = null
  let manualClose = false
  let reconnectTimer = null
  let reconnectDelay = 1000
  const MAX_DELAY = 30000

  const setStatus = (connected, reason) => {
    if (typeof onStatus === 'function') {
      onStatus({ connected, reason: reason || '' })
    }
  }

  const connect = () => {
    manualClose = false
    try {
      ws = new WebSocket(`${WS_BASE}/api/ws?subscribe=${encodeURIComponent(scope)}`)
    } catch (e) {
      setStatus(false, '不支持 WebSocket')
      return
    }

    ws.addEventListener('open', () => {
      reconnectDelay = 1000
      setStatus(true, 'connected')
    })

    ws.addEventListener('message', (event) => {
      let msg = null
      try {
        msg = typeof event.data === 'string' ? JSON.parse(event.data) : null
      } catch (_) { return }
      if (!msg) return

      if (msg.type === 'update' && typeof onUpdate === 'function') {
        onUpdate({ serverId: msg.serverId, data: msg.data })
      }
      if (typeof onMessage === 'function') onMessage(msg)
    })

    ws.addEventListener('close', () => {
      setStatus(false, 'disconnected')
      scheduleReconnect()
    })

    ws.addEventListener('error', () => {
      setStatus(false, 'error')
      // 浏览器会在 error 后紧接着触发 close，reconnect 交由 close 处理
      try { ws.close() } catch (_) {}
    })
  }

  const scheduleReconnect = () => {
    if (manualClose) return
    if (reconnectTimer) return
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      // 指数退避
      const delay = reconnectDelay
      reconnectDelay = Math.min(reconnectDelay * 2, MAX_DELAY)
      setTimeout(connect, delay)
    }, 50)
  }

  connect()

  return {
    close() {
      manualClose = true
      if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null }
      if (ws) { try { ws.close() } catch (_) {} ws = null }
    },
    reconnect() {
      manualClose = false
      if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null }
      if (ws) { try { ws.close() } catch (_) {} ws = null }
      connect()
    }
  }
}

export const getAuthHeader = () => {
  const token = localStorage.getItem('jwt_token')
  if (!token) return {}
  return { 'Authorization': 'Bearer ' + token }
}

export const getTurnstileHeader = () => {
  const token = localStorage.getItem('turnstile_token')
  if (token) {
    return { 'X-Turnstile-Token': token }
  }
  return {}
}

export const isAdminLoggedIn = () => {
  return !!localStorage.getItem('jwt_token')
}

export const formatBytes = (bytes) => {
  bytes = parseFloat(bytes) || 0
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

export const fetchServers = async () => {
  const res = await fetch(`${API_BASE}/api/servers`, {
    headers: {
      ...getAuthHeader(),
      ...getTurnstileHeader()
    }
  })
  if (res.status === 401) {
    window.location.href = '/admin'
    return null
  }
  if (res.status === 403) {
    localStorage.removeItem('turnstile_token')
    window.location.reload()
    return null
  }
  if (!res.ok) throw new Error('Failed to fetch')
  return await res.json()
}

export const fetchServerDetail = async (id) => {
  const res = await fetch(`${API_BASE}/api/server?id=${id}`, {
    headers: {
      ...getAuthHeader(),
      ...getTurnstileHeader()
    }
  })
  if (res.status === 401) {
    window.location.href = '/admin'
    return null
  }
  if (res.status === 403) {
    localStorage.removeItem('turnstile_token')
    window.location.reload()
    return null
  }
  if (!res.ok) throw new Error('Failed to fetch')
  return await res.json()
}

export const fetchServerHistory = async (id, metric, hours) => {
  const res = await fetch(`${API_BASE}/api/history?id=${id}&metric=${metric}&hours=${hours}`, {
    headers: {
      ...getAuthHeader(),
      ...getTurnstileHeader()
    }
  })
  if (res.status === 401) {
    window.location.href = '/admin'
    return []
  }
  if (res.status === 403) {
    localStorage.removeItem('turnstile_token')
    window.location.reload()
    return []
  }
  if (!res.ok) return []
  return await res.json()
}

export const fetchAllHistory = async (id, hours) => {
  const res = await fetch(`${API_BASE}/api/history/all?id=${id}&hours=${hours}`, {
    headers: {
      ...getAuthHeader(),
      ...getTurnstileHeader()
    }
  })
  if (res.status === 401) {
    window.location.href = '/admin'
    return null
  }
  if (res.status === 403) {
    localStorage.removeItem('turnstile_token')
    window.location.reload()
    return null
  }
  if (!res.ok) return null
  return await res.json()
}

export const adminApi = async (data) => {
  const res = await fetch(`${API_BASE}/admin/api`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...getAuthHeader(),
      ...getTurnstileHeader()
    },
    body: JSON.stringify(data)
  })
  if (res.status === 401) {
    localStorage.removeItem('jwt_token')
    window.location.href = '/admin'
  }
  return res
}

export const login = async (username, password, turnstileToken = '') => {
  const headers = {
    'Content-Type': 'application/json'
  }
  if (turnstileToken) {
    headers['X-Turnstile-Token'] = turnstileToken
  }
  const res = await fetch(`${API_BASE}/admin/api`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ action: 'login', username, password })
  })
  if (res.ok) {
    const data = await res.json()
    if (data.token) {
      localStorage.setItem('jwt_token', data.token)
    }
  }
  return res
}

export const logout = () => {
  localStorage.removeItem('jwt_token')
}

export const fetchConfig = async () => {
  const res = await fetch(`${API_BASE}/api/config`)
  if (!res.ok) return null
  return await res.json()
}

export const upgradeDatabase = async () => {
  const res = await fetch(`${API_BASE}/updateDatabase`, {
    headers: getAuthHeader()
  })
  if (!res.ok) {
    if (res.status === 401) {
      return { success: false, error: 'Unauthorized' }
    }
    return { success: false, error: 'Request failed' }
  }
  return await res.json()
}

export const rebuildDatabase = async () => {
  const res = await fetch(`${API_BASE}/rebuild`, {
    headers: getAuthHeader()
  })
  if (!res.ok) {
    if (res.status === 401) {
      return { success: false, error: 'Unauthorized' }
    }
    return { success: false, error: 'Request failed' }
  }
  return await res.json()
}