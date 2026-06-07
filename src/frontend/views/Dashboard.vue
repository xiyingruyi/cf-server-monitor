<template>
  <div class="container">
    <TerminalHeader :title="sysConfig.site_title || 'Server Monitor'" />
    
    <div class="nav-area">
      <div class="header-row">
        <div class="site-title">$ ./{{ sysConfig.site_title || 'Server Monitor' }}</div>
        <div class="controls-group">
          <div class="view-toggle">
            <button 
              class="toggle-btn" 
              :class="{ active: currentView === 'card' }"
              @click="switchView('card')"
            >▣ {{ trans.cards }}</button>
            <button 
              class="toggle-btn" 
              :class="{ active: currentView === 'table' }"
              @click="switchView('table')"
            >≡ {{ trans.table }}</button>
            <button 
              class="toggle-btn" 
              :class="{ active: currentView === 'map' }"
              @click="switchView('map')"
            >◉ {{ trans.map }}</button>
          </div>
          <a href="/admin" class="admin-link">⚙ {{ sysConfig.admin_title || 'Admin' }}</a>
        </div>
      </div>
      <div class="filter-bar" id="ajax-filters">
        <span 
          v-for="(count, code) in filterOptions" 
          :key="code"
          class="filter-tag"
          :class="{ active: currentFilter === code }"
          :data-filter="code"
          @click="setFilter(code)"
        >
          <span v-if="code !== 'all'">
            <img v-if="code !== 'all'" :src="'https://flagcdn.com/16x12/' + (code || 'xx').toLowerCase() + '.png'" :alt="code">
          </span>
          {{ code === 'all' ? '[' + trans.all + ']' : code.toUpperCase() }} {{ count }}
        </span>
      </div>
    </div>

    <div class="global-stats">
      <div class="stat-item">
        <div class="stat-label">{{ trans.totalServers }}</div>
        <div class="stat-main-value">{{ stats.total }}</div>
        <div class="stat-sub-info">
          <span class="stat-online-color">{{ trans.online }}:{{ stats.online }}</span> |
          <span class="stat-offline-color">{{ trans.offline }}:{{ stats.offline }}</span>
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-label">{{ trans.totalTraffic }}</div>
        <div class="stat-main-value stat-main-value-sm">{{ formatBytes(stats.globalNetRx) }} ↓ | ↑ {{ formatBytes(stats.globalNetTx) }}</div>
      </div>
      <div class="stat-item">
        <div class="stat-label">{{ trans.realtimeSpeed }}</div>
        <div class="stat-main-value stat-main-value-sm">
          <span class="stat-net-down-color">↓ {{ formatBytes(stats.globalSpeedIn) }}/s</span> |
          <span class="stat-net-up-color">↑ {{ formatBytes(stats.globalSpeedOut) }}/s</span>
        </div>
      </div>
    </div>

    <div id="view-card" class="view-panel" :class="{ active: currentView === 'card' }">
      <div v-if="groupedServers.length === 0" class="empty-state">
        [!] {{ trans.noServer }}，请在 <a href="/admin" class="admin-link-color">{{ trans.backToAdmin }}</a> 中添加
      </div>
      <div v-else>
        <div v-for="group in groupedServers" :key="group.name" class="group-section">
          <div class="group-header" :data-group="group.name">
            <span class="prompt-sign">#</span> {{ group.name }} <span class="group-count">[{{ group.servers.length }}]</span>
          </div>
          <div class="servers-grid">
            <ServerCard 
              v-for="server in group.servers" 
              :key="server.id" 
              :server="server"
              :sys-config="sysConfig"
            />
          </div>
        </div>
      </div>
    </div>

    <div id="view-table" class="view-panel" :class="{ active: currentView === 'table' }">
      <div class="table-container">
        <table class="terminal-table">
          <thead>
            <tr>
              <th>{{ trans.hostname.substring(0, 4) }}</th>
              <th>{{ trans.hostname }}</th>
              <th>{{ trans.region }}</th>
              <th>{{ trans.osArch }}</th>
              <th>{{ trans.cpu }}</th>
              <th>{{ trans.ram }}</th>
              <th>{{ trans.disk }}</th>
              <th>{{ trans.dl }}</th>
              <th>{{ trans.ul }}</th>
              <th>{{ trans.rx }}</th>
              <th>{{ trans.tx }}</th>
              <th>{{ trans.update }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="filteredServers.length === 0">
              <td colspan="12" class="table-empty-state">[*] {{ trans.noData }}</td>
            </tr>
            <tr 
              v-for="server in filteredServers" 
              :key="server.id"
              @click="goToServer(server.id)"
              class="table-cursor-pointer"
              :data-country="(server.country || 'xx').toLowerCase()"
            >
              <td class="table-center-cell">
                <div class="status-indicator table-status-indicator-inline" :style="{ background: getStatusColor(server) }"></div>
              </td>
              <td><b>{{ server.name }}</b></td>
              <td>
                <span v-if="server.country && server.country !== 'xx'">
                  <img :src="'https://flagcdn.com/24x18/' + server.country.toLowerCase() + '.png'" :alt="server.country" class="flag-img">
                </span>
                <span v-else>🏳️</span>
                {{ (server.country || 'XX').toUpperCase() }}
              </td>
              <td><span class="os-label">{{ server.os || 'N/A' }} / {{ server.arch || 'N/A' }} </span></td>
              <td>
                <div class="table-stat">
                  <div class="stat-bar-container stat-bar-small">
                  <div class="stat-bar-fill" :style="{ width: (parseFloat(server.cpu) || 0) + '%', background: 'var(--accent-cyan)' }"></div>
                </div>
                  <span>{{ (parseFloat(server.cpu) || 0).toFixed(1) }}%</span>
                </div>
              </td>
              <td>
                <div class="table-stat">
                  <div class="stat-bar-container" style="width:60px;">
                    <div class="stat-bar-fill" :style="{ width: (parseFloat(server.ram) || 0) + '%', background: 'var(--accent-purple)' }"></div>
                  </div>
                  <span>{{ (parseFloat(server.ram) || 0).toFixed(1) }}%</span>
                </div>
              </td>
              <td>
                <div class="table-stat">
                  <div class="stat-bar-container" style="width:60px;">
                    <div class="stat-bar-fill" :style="{ width: (parseFloat(server.disk) || 0) + '%', background: 'var(--accent-green)' }"></div>
                  </div>
                  <span>{{ (parseFloat(server.disk) || 0).toFixed(1) }}%</span>
                </div>
              </td>
              <td>{{ formatBytes(server.net_in_speed) }}/s</td>
              <td>{{ formatBytes(server.net_out_speed) }}/s</td>
              <td>{{ formatBytes(server.net_rx) }}</td>
              <td>{{ formatBytes(server.net_tx) }}</td>
              <td class="update-time">{{ getUpdateTime(server.last_updated) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div id="view-map" class="view-panel" :class="{ active: currentView === 'map' }">
      <div class="map-wrapper">
        <div ref="mapContainer" id="map-container"></div>
      </div>
    </div>

    <Footer />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import TerminalHeader from '../components/TerminalHeader.vue'
import ServerCard from '../components/ServerCard.vue'
import Footer from '../components/Footer.vue'
import { fetchServers, formatBytes, createLiveSocket } from '../utils/api.js'
import { t, currentLang } from '../utils/i18n.js'
import { translations } from '../utils/i18n.js'

const servers = ref([])
const stats = ref({ total: '-', online: 0, offline: 0, globalNetRx: 0, globalNetTx: 0, globalSpeedIn: 0, globalSpeedOut: 0 })
const sysConfig = ref({
  show_price: true,
  show_expire: true,
  show_bw: true,
  show_tf: true,
  site_title: 'Server Monitor',
  admin_title: 'Admin'
})
const countryStats = ref({})
const currentView = ref('card')
const currentFilter = ref('all')
const mapInitialized = ref(false)
const liveConnected = ref(false)

const trans = computed(() => translations[currentLang.value] || translations.en)

const filterOptions = computed(() => {
  const normalizedStats = {}
  for (const code in countryStats.value) {
    normalizedStats[code.toLowerCase()] = countryStats.value[code]
  }
  return { all: stats.value.total, ...normalizedStats }
})

const groupedServers = computed(() => {
  const groups = {}
  const order = []
  const filteredList = currentFilter.value === 'all' ? servers.value : servers.value.filter(s => (s.country || 'xx').toLowerCase() === currentFilter.value)
  filteredList.forEach(server => {
    const groupName = server.server_group || 'Default'
    if (!groups[groupName]) {
      groups[groupName] = []
      order.push(groupName)
    }
    groups[groupName].push(server)
  })
  return order.map(name => ({ name, servers: groups[name] }))
})

const filteredServers = computed(() => {
  if (currentFilter.value === 'all') return servers.value
  return servers.value.filter(s => (s.country || 'xx').toLowerCase() === currentFilter.value)
})

const switchView = (viewName) => {
  currentView.value = viewName
  localStorage.setItem('monitor_preferred_view', viewName)
  if (viewName === 'map' && !mapInitialized.value) {
    initMap()
    mapInitialized.value = true
  } else if (viewName === 'map' && window.myMap) {
    setTimeout(() => window.myMap.invalidateSize(), 100)
  }
}

const setFilter = (code) => {
  currentFilter.value = code.toLowerCase()
}

const getStatusColor = (server) => {
  const lastUpdated = new Date(server.last_updated).getTime()
  return (Date.now() - lastUpdated) < 300000 ? 'var(--accent-green)' : 'var(--accent-red)'
}

const getUpdateTime = (lastUpdated) => {
  if (!lastUpdated) return '-'
  const date = new Date(lastUpdated)
  return date.toLocaleString(undefined, { hour12: false })
}

// 用最新数据增量更新单台服务器信息
// 无论后端 last_updated 是否变化，都用前端收到推送的时间更新 last_updated，
// 保证实时时间列（"xx:xx:xx ago"）在每次推送时都刷新。
const mergeServerUpdate = (data) => {
  if (!data || !data.id) return false
  const idx = servers.value.findIndex(s => s.id === data.id)
  if (idx >= 0) {
    // 已有服务器：合并字段，同时更新 last_updated 为前端收到时间
    servers.value[idx] = { ...servers.value[idx], ...data, last_updated: Date.now() }
  } else {
    // 新服务器：加入列表
    servers.value.push({ ...data, name: data.id, last_updated: Date.now() })
  }
  return true
}

const recomputeStats = () => {
  const list = servers.value || []
  const now = Date.now()
  let online = 0
  let speedIn = 0, speedOut = 0, netRx = 0, netTx = 0
  const countryCounts = {}
  for (const s of list) {
    const ts = new Date(s.last_updated || 0).getTime()
    const isOnline = ts && (now - ts) < 300000
    if (isOnline) {
      online++
      speedIn += parseFloat(s.net_in_speed) || 0
      speedOut += parseFloat(s.net_out_speed) || 0
    }
    netRx += parseFloat(s.net_rx) || 0
    netTx += parseFloat(s.net_tx) || 0
    if (s.country) {
      const key = String(s.country).toUpperCase()
      countryCounts[key] = (countryCounts[key] || 0) + 1
    }
  }
  stats.value = {
    total: list.length,
    online,
    offline: list.length - online,
    globalNetRx: netRx,
    globalNetTx: netTx,
    globalSpeedIn: speedIn,
    globalSpeedOut: speedOut
  }
  countryStats.value = countryCounts
}

const refreshData = async () => {
  try {
    const data = await fetchServers()
    if (!data) return

    // 合并已有列表与最新服务端全量数据（优先使用服务端返回的 name/group 等完整字段）
    const existingById = new Map(servers.value.map(s => [s.id, s]))
    const nextList = (data.servers || []).map(s => {
      const prev = existingById.get(s.id)
      // 取服务端返回作为权威数据，并保留本地字段以防服务端缺少
      return { ...prev, ...s }
    })
    servers.value = nextList

    if (data.stats) stats.value = data.stats
    if (data.countryStats) countryStats.value = data.countryStats

    sysConfig.value = {
      show_price: data.sysConfig?.show_price ?? true,
      show_expire: data.sysConfig?.show_expire ?? true,
      show_bw: data.sysConfig?.show_bw ?? true,
      show_tf: data.sysConfig?.show_tf ?? true,
      site_title: data.sysConfig?.site_title || 'Server Monitor',
      admin_title: data.sysConfig?.admin_title || 'Admin'
    }

    drawMarkers()
  } catch (e) {
    console.log('[INFO] Full refresh pending...', e)
  }
}

// -------------------------------------------------------------------------
// 实时推送：
//   - 订阅 "all"，收到任何服务器的更新都会合并对应 server 的指标
//   - WS 连上后关闭 60s 兜底轮询；断开后临时开启作为降级（WS 重连成功后再次清除）
// -------------------------------------------------------------------------
let liveSocket = null
let refreshInterval = null
let themeObserver = null

const applyLiveUpdate = ({ serverId, data }) => {
  if (!data || !serverId) return
  mergeServerUpdate(data)
  recomputeStats()
  if (currentView.value === 'map') drawMarkers()
}

const startLiveSocket = () => {
  liveSocket = createLiveSocket('all', {
    onUpdate: applyLiveUpdate,
    onStatus: ({ connected }) => {
      liveConnected.value = !!connected
      if (connected) {
        // WS 可用，清除定时轮询
        if (refreshInterval) { clearInterval(refreshInterval); refreshInterval = null }
      } else if (!refreshInterval) {
        // WS 断开，降级启用 60s 轮询直到重连成功
        refreshInterval = setInterval(refreshData, 60000)
      }
    }
  })
}

const initMap = () => {
  if (!window.L) {
    const script = document.createElement('script')
    script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
    script.onload = () => {
      loadLeafletCSS()
    }
    document.head.appendChild(script)
  } else {
    loadLeafletCSS()
  }
}

const loadLeafletCSS = () => {
  const link = document.createElement('link')
  link.rel = 'stylesheet'
  link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'
  document.head.appendChild(link)
  link.onload = () => {
    createMap()
  }
}

const createMap = () => {
  window.myMap = window.L.map('map-container', {
    zoomControl: false,
    attributionControl: false,
    minZoom: 1
  }).setView([30, 10], 2)

  window.L.control.zoom({ position: 'bottomright' }).addTo(window.myMap)

  fetch('https://cdn.jsdelivr.net/gh/johan/world.geo.json@master/countries.geo.json')
    .then(res => res.json())
    .then(worldGeoJson => {
      window.worldGeoJson = worldGeoJson
      drawMarkers()
    })
    .catch(e => console.error('[ERROR] Map load failed', e))
}

const countryCoords = {
  'US': [37.09, -95.71], 'CN': [35.86, 104.19], 'JP': [36.20, 138.25], 'HK': [22.31, 114.16],
  'SG': [1.35, 103.81], 'KR': [35.90, 127.76], 'DE': [51.16, 10.45], 'GB': [55.37, -3.43],
  'NL': [52.13, 5.29], 'FR': [46.22, 2.21], 'CA': [56.13, -106.34], 'AU': [-25.27, 133.77],
  'IN': [20.59, 78.96], 'BR': [-14.23, -51.92], 'RU': [61.52, 105.31], 'ZA': [-30.55, 22.93],
  'TW': [23.69, 120.96], 'IT': [41.87, 12.56], 'SE': [60.12, 18.64], 'CH': [46.81, 8.22],
  'ES': [40.46, -3.74], 'PL': [51.91, 19.14], 'FI': [61.92, 25.74], 'NO': [60.47, 8.46],
  'DK': [56.26, 9.50], 'IE': [53.14, -7.69], 'AT': [47.51, 14.55], 'TR': [38.96, 35.24],
  'AE': [23.42, 53.84], 'MY': [4.21, 101.97], 'TH': [15.87, 100.99], 'VN': [14.05, 108.27],
  'PH': [12.87, 121.77], 'ID': [-0.78, 113.92]
}

const iso2To3 = {
  "US":"USA","CN":"CHN","JP":"JPN","HK":"HKG","SG":"SGP","KR":"KOR","DE":"DEU","GB":"GBR",
  "NL":"NLD","FR":"FRA","CA":"CAN","AU":"AUS","IN":"IND","BR":"BRA","RU":"RUS","ZA":"ZAF",
  "TW":"TWN","IT":"ITA","SE":"SWE","CH":"CHE","ES":"ESP","PL":"POL","FI":"FIN","NO":"NOR",
  "DK":"DNK","IE":"IRL","AT":"AUT","TR":"TUR","AE":"ARE","MY":"MYS","TH":"THA","VN":"VNM",
  "PH":"PHL","ID":"IDN"
}

let markersLayer, geoJsonLayer, currentMapDataStr = ""

const getThemeColors = () => {
  const isLight = document.body.classList.contains('light')
  return {
    bgPrimary: isLight ? '#0a0e14' : '#0a0e14',
    bgSecondary: isLight ? '#e8e8e0' : '#12171f',
    borderColor: isLight ? '#1e2a3a' : '#1e2a3a',
    accentGreen: isLight ? '#00d4aa' : '#00d4aa',
    colorBlack: isLight ? '#000' : '#000',
    colorWhite: isLight ? '#fff' : '#fff'
  }
}

const drawMarkers = () => {
  if (!window.myMap || !window.worldGeoJson) return

  const newDataStr = JSON.stringify(countryStats.value)
  if (currentMapDataStr === newDataStr) return
  currentMapDataStr = newDataStr

  if (geoJsonLayer) window.myMap.removeLayer(geoJsonLayer)
  if (markersLayer) markersLayer.clearLayers()
  else markersLayer = window.L.layerGroup().addTo(window.myMap)

  const colors = getThemeColors()
  const activeIso3 = {}
  for (const code in countryStats.value) {
    if (iso2To3[code.toUpperCase()]) activeIso3[iso2To3[code.toUpperCase()]] = true
  }

  geoJsonLayer = window.L.geoJSON(window.worldGeoJson, {
    style: function(feature) {
      const isActive = activeIso3[feature.id]
      return {
        fillColor: isActive ? colors.accentGreen : colors.borderColor,
        weight: 1,
        opacity: 0.8,
        color: colors.bgPrimary,
        fillOpacity: isActive ? 0.4 : 0.2
      }
    }
  }).addTo(window.myMap)

  for (const [code, count] of Object.entries(countryStats.value)) {
    const upperCode = code.toUpperCase()
    if (countryCoords[upperCode]) {
      const icon = window.L.divIcon({
        className: 'custom-map-marker',
        html: `<div style="background:${colors.accentGreen}; color:${colors.colorBlack}; border-radius:50%; width:22px; height:22px; display:flex; align-items:center; justify-content:center; font-size:10px; font-weight:bold; border:2px solid ${colors.bgPrimary}; box-shadow:0 0 10px ${colors.accentGreen}80; font-family:JetBrains Mono,monospace;">${count}</div>`,
        iconSize: [22,22]
      })
      window.L.marker(countryCoords[upperCode], {icon: icon}).addTo(markersLayer)
    }
  }
}

const goToServer = (id) => {
  window.location.href = `/server/${id}`
}

onMounted(() => {
  const savedView = localStorage.getItem('monitor_preferred_view') || 'card'
  currentView.value = savedView
  refreshData()
  startLiveSocket()

  if (savedView === 'map') {
    switchView('map')
  }

  themeObserver = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      if (mutation.attributeName === 'class' && currentView.value === 'map') {
        currentMapDataStr = ''
        drawMarkers()
      }
    })
  })
  themeObserver.observe(document.body, { attributes: true, attributeFilter: ['class'] })
})

onUnmounted(() => {
  if (refreshInterval) clearInterval(refreshInterval)
  if (liveSocket) liveSocket.close()
  if (themeObserver) themeObserver.disconnect()
})
</script>