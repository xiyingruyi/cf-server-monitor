import { createApp } from 'vue'
import App from './App.vue'
import router from './router'
import './styles/main.css'
import './styles/light.css'

const API_BASE = window.location.origin

async function fetchConfig() {
  try {
    const res = await fetch(`${API_BASE}/api/config`)
    if (res.ok) {
      return await res.json()
    }
  } catch (e) {
    console.error('Failed to fetch config:', e)
  }
  return { turnstile_enabled: false, turnstile_site_key: '' }
}

async function loadTurnstileScript() {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js'
    script.async = true
    script.onload = resolve
    script.onerror = reject
    document.head.appendChild(script)
  })
}

function hasValidTurnstileCookie() {
  const cookies = document.cookie.split(';')
  for (const cookie of cookies) {
    const [name, value] = cookie.trim().split('=')
    if (name === 'turnstile_verified' && value) {
      return true
    }
  }
  return false
}

async function verifyTurnstile(siteKey) {
  return new Promise((resolve) => {
    turnstile.render('#turnstile-container', {
      sitekey: siteKey,
      callback: async (token) => {
        localStorage.setItem('turnstile_token', token)
        try {
          const res = await fetch(`${API_BASE}/api/servers`, {
            headers: { 'X-Turnstile-Token': token }
          })
          if (res.ok) {
            resolve(true)
          } else {
            resolve(false)
          }
        } catch (e) {
          console.error('Failed to verify token:', e)
          resolve(false)
        }
      },
      errorCallback: (error) => {
        console.error('Turnstile error:', error)
        resolve(false)
      },
      expiredCallback: () => {
        localStorage.removeItem('turnstile_token')
        resolve(false)
      }
    })
  })
}

async function initApp() {
  const config = await fetchConfig()
  
  if (config.turnstile_enabled && config.turnstile_site_key && !config.cookie_auth) {
    const loading = document.getElementById('loading')
    if (loading) {
      loading.innerHTML = `
        <div class="loading-content">
          <div class="loading-spinner"></div>
          <div class="loading-text">$ Verifying...</div>
          <div id="turnstile-container" style="margin-top: 20px;"></div>
        </div>
      `
    }
    
    try {
      await loadTurnstileScript()
      const verified = await verifyTurnstile(config.turnstile_site_key)
      
      if (!verified) {
        loading.innerHTML = `
          <div class="loading-content">
            <div style="font-size: 48px; margin-bottom: 16px;">❌</div>
            <div class="loading-text" style="color: #f85149;">Verification failed</div>
            <div style="font-size: 12px; color: #6b7280; margin-top: 8px;">Please refresh the page to try again</div>
          </div>
        `
        return
      }
    } catch (e) {
      console.error('Turnstile error:', e)
      loading.innerHTML = `
        <div class="loading-content">
          <div style="font-size: 48px; margin-bottom: 16px;">❌</div>
          <div class="loading-text" style="color: #f85149;">Verification error</div>
          <div style="font-size: 12px; color: #6b7280; margin-top: 8px;">${e.message}</div>
        </div>
      `
      return
    }
  }
  
  const app = createApp(App)
  app.use(router)
  app.mount('#app').$nextTick(() => {
    const loading = document.getElementById('loading')
    if (loading) {
      setTimeout(() => {
        loading.remove()
      }, 1000)
    }
  })
}

initApp()