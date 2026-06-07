<template>
  <div>
    <div v-if="!isLoggedIn" id="login-overlay" class="login-overlay">
      <div class="login-container">
        <div class="login-header">
          <div class="login-icon">🔐</div>
          <h2 class="login-title">{{ trans.adminLogin }}</h2>
          <p class="login-subtitle">{{ trans.enterCredentials }}</p>
        </div>
        <form @submit.prevent="handleLogin">
          <div class="login-form-group">
            <label class="login-label">{{ trans.username }}</label>
            <input type="text" v-model="loginForm.username" required class="login-input" placeholder="admin">
          </div>
          <div class="login-form-group last">
            <label class="login-label">{{ trans.password }}</label>
            <div class="password-input-wrapper">
              <input :type="passwordVisible.login ? 'text' : 'password'" v-model="loginForm.password" required class="login-input" placeholder="••••••••">
              <button type="button" class="password-toggle" @click="togglePassword('login')">
                {{ passwordVisible.login ? '🙈' : '👁️' }}
              </button>
            </div>
          </div>
          <div v-if="turnstileEnabled && turnstileSiteKey" class="login-form-group">
            <div id="admin-turnstile-container"></div>
          </div>
          <div v-if="loginError" id="login-error" class="login-error">{{ loginError }}</div>
          <button type="submit" class="login-btn">{{ loginLoading ? '⏳' : trans.login }}</button>
        </form>
      </div>
    </div>

    <div v-else class="container" id="admin-content">
      <TerminalHeader :title="settings.admin_title || trans.adminPanel" />
      
      <div class="main-panel">
        <div class="panel-header">
          <div class="panel-title">
            <span class="prompt">$</span> {{ trans.sudoStatus }}
          </div>
          <div class="header-actions">
            <button @click="refreshStats" class="btn">↻ {{ trans.refresh }}</button>
            <button @click="logout" class="btn btn-red">🚪 {{ trans.logout }}</button>
            <a href="/" class="btn">▸ {{ trans.dashboard }}</a>
          </div>
        </div>

        <div class="stats-grid" id="stats-panel">
          <div class="stat-card">
            <div class="stat-main-value" id="stat-total">{{ stats.total }}</div>
            <div class="stat-label">{{ trans.totalServers }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-main-value" id="stat-online">{{ stats.online }}</div>
            <div class="stat-label">{{ trans.online }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-main-value" id="stat-offline">{{ stats.offline }}</div>
            <div class="stat-label">{{ trans.offline }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-main-value" id="stat-avg-cpu">{{ stats.avg_cpu }}%</div>
            <div class="stat-label">{{ trans.avgCpu }}</div>
          </div>
        </div>
      </div>

      <div class="main-panel">
        <div class="tabs">
          <button 
            class="tab-btn" 
            :class="{ active: activeTab === 'servers' }"
            @click="activeTab = 'servers'"
          >▸ {{ trans.servers }}</button>
          <button 
            class="tab-btn" 
            :class="{ active: activeTab === 'settings' }"
            @click="activeTab = 'settings'"
          >▸ {{ trans.settings }}</button>
          <button 
            class="tab-btn" 
            :class="{ active: activeTab === 'database' }"
            @click="activeTab = 'database'"
          >▸ {{ trans.dbManagement }}</button>
        </div>

        <div id="tab-servers" class="tab-content" :class="{ active: activeTab === 'servers' }">
          <div class="alert alert-info">
            <span class="alert-icon">[i]</span>
            <span>{{ trans.clickToCopy }} <strong>📋</strong> {{ trans.installCommand }}。{{ trans.interval }}</span>
          </div>

          <div class="toolbar">
            <input type="text" v-model="newServerName" class="toolbar-input" :placeholder="'> ' + trans.serverName + '...'">
            <select v-model="newServerGroup" class="toolbar-select">
              <option v-for="group in groups" :key="group" :value="group">{{ group }}</option>
            </select>
            <button @click="addServer" class="btn btn-primary">+ {{ trans.addServer }}</button>
          </div>

          <div class="batch-actions">
            <button @click="batchDelete" class="btn btn-red">🗑 {{ trans.batchDelete }}</button>
            <button @click="toggleSelectAll" class="btn">☐ {{ trans.toggleAll }}</button>
          </div>

          <div class="table-wrapper">
            <table class="terminal-table">
              <thead>
                <tr>
                  <th class="table-center-cell" style="width:35px;">↕️</th>
                  <th style="width:30px;"><input type="checkbox" id="select-all" @change="handleSelectAll" style="accent-color: var(--accent-green);"></th>
                  <th>{{ trans.hostname.toUpperCase() }}</th>
                  <th>{{ trans.group.toUpperCase() }}</th>
                  <th>{{ trans.price.toUpperCase() }}</th>
                  <th>{{ trans.expire.toUpperCase() }}</th>
                  <th>{{ trans.bandwidth.toUpperCase() }}</th>
                  <th>{{ trans.traffic.toUpperCase() }}</th>
                  <th>{{ trans.status.toUpperCase() }}</th>
                  <th>{{ trans.actions.toUpperCase() }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-if="servers.length === 0">
                  <td colspan="10" class="empty-state"><span class="empty-icon">📦</span> {{ trans.noServers }}</td>
                </tr>
                <tr 
                  v-for="server in servers" 
                  :key="server.id"
                  class="server-row"
                  :data-server-id="server.id"
                >
                  <td class="drag-handle table-center-cell" :title="trans.dragSort" draggable="true" @dragstart="handleDragStart" @dragover.prevent @drop="handleDrop($event, server.id)">⋮⋮</td>
                  <td class="table-center-cell"><input type="checkbox" class="server-checkbox" :value="server.id" v-model="selectedServers"></td>
                  <td>
                    <div style="display:flex; align-items:center; gap:8px;">
                      <span v-if="server.country && server.country !== 'xx'">
                        <img :src="'https://flagcdn.com/24x18/' + server.country.toLowerCase() + '.png'" :alt="server.country" style="vertical-align: middle; border-radius: 2px; filter: brightness(0.9);">
                      </span>
                      <span v-else>🏳️</span>
                      <a :href="'/server/' + server.id" style="color:var(--text-primary); font-weight:bold; text-decoration:none;">{{ server.name }}</a>
                    </div>
                  </td>
                  <td><span class="group-tag">{{ server.server_group || trans.default }}</span></td>
                  <td><span class="price-tag">{{ server.price || '-' }}</span></td>
                  <td><span class="date-text">{{ server.expire_date || '-' }}</span></td>
                  <td><span class="spec-text">{{ server.bandwidth || '-' }}</span></td>
                  <td><span class="spec-text">{{ server.traffic_limit || '-' }}</span></td>
                  <td>
                    <span :style="{ color: getStatusColor(server), fontWeight: 'bold' }">{{ getStatusText(server) }}</span>
                  </td>
                  <td>
                    <div class="action-group">
                      <div class="cmd-input-wrapper" :class="{ copied: copiedServerId === server.id }">
                        <span class="cmd-prompt">$</span>
                        <input @click="copyCmd(server.id)" type="text" readonly :value="getInstallCommand(server.id)" class="cmd-input">
                      </div>
                      <div class="action-btns">
                        <button @click="copyCmd(server.id)" class="btn btn-icon btn-green" :title="trans.copy">{{ copiedServerId === server.id ? '✅' : '📋' }}</button>
                        <button @click="openEditModal(server)" class="btn btn-icon btn-blue" :title="trans.edit">✏️</button>
                        <button @click="openDeleteModal(server.id)" class="btn btn-icon btn-red" :title="trans.delete">🗑️</button>
                      </div>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div id="tab-settings" class="tab-content" :class="{ active: activeTab === 'settings' }">
          <div class="settings-grid">
            <div class="settings-section">
              <div class="section-title"><span>▸</span> {{ trans.appearance }}</div>

              <div class="form-group">
                <label class="form-label">{{ trans.siteTitle }}</label>
                <input type="text" v-model="settings.site_title" class="form-input" :placeholder="'Cloudflare Server Monitor'">
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.adminTitle }}</label>
                <input type="text" v-model="settings.admin_title" class="form-input" :placeholder="'Admin Panel'">
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.bgImage }}</label>
                <div style="display:flex; gap:8px;">
                  <input type="text" v-model="settings.custom_bg" class="form-input" placeholder="https://..." style="flex:1;">
                  <div class="upload-btn-wrapper">
                    <button class="btn" style="margin:0;">📁 {{ trans.upload }}</button>
                    <input type="file" accept="image/*" @change="uploadBg">
                  </div>
                </div>
                <img v-if="settings.custom_bg" :src="settings.custom_bg" class="bg-preview">
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.customHead }}</label>
                <textarea v-model="settings.custom_head" class="form-textarea" rows="3" placeholder="<link rel='stylesheet' href='...'">
                </textarea>
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.customScript }}</label>
                <textarea v-model="settings.custom_script" class="form-textarea" rows="4" placeholder="console.log('Hello');">
                </textarea>
              </div>
            </div>

            <div>
              <div class="settings-section" style="margin-bottom: 20px;">
                <div class="section-title"><span>▸</span> {{ trans.displayOptions }}</div>

                <div class="checkbox-item">
                  <input type="checkbox" id="cfg_is_public" v-model="settings.is_public">
                  <label><b>{{ trans.publicAccess }}</b></label>
                </div>

                <div class="checkbox-item">
                  <input type="checkbox" id="cfg_show_price" v-model="settings.show_price">
                  <label>{{ trans.showPrice }}</label>
                </div>

                <div class="checkbox-item">
                  <input type="checkbox" id="cfg_show_expire" v-model="settings.show_expire">
                  <label>{{ trans.showExpire }}</label>
                </div>

                <div class="checkbox-item">
                  <input type="checkbox" id="cfg_show_bw" v-model="settings.show_bw">
                  <label>{{ trans.showBw }}</label>
                </div>

                <div class="checkbox-item">
                  <input type="checkbox" id="cfg_show_tf" v-model="settings.show_tf">
                  <label>{{ trans.showTf }}</label>
                </div>
              </div>

              <div class="settings-section">
                <div class="section-title"><span>▸</span> {{ trans.notifications }}</div>

                <div class="form-group">
                  <label class="form-label">{{ trans.offlineAlert }}</label>
                  <select v-model="settings.tg_notify" class="form-select">
                    <option value="false">[OFF] {{ trans.disabled }}</option>
                    <option value="true">[ON] {{ trans.notifyOffline }}</option>
                  </select>
                </div>

                <div class="form-group">
                  <label class="form-label">{{ trans.telegramToken }}</label>
                  <div class="password-input-wrapper">
                    <input :type="passwordVisible.tgBotToken ? 'text' : 'password'" v-model="settings.tg_bot_token" class="form-input" placeholder="Bot Token or Webhook URL">
                    <button type="button" class="password-toggle" @click="togglePassword('tgBotToken')">
                      {{ passwordVisible.tgBotToken ? '🙈' : '👁️' }}
                    </button>
                  </div>
                </div>

                <div class="form-group">
                  <label class="form-label">{{ trans.chatId }}</label>
                  <div class="password-input-wrapper">
                    <input :type="passwordVisible.tgChatId ? 'text' : 'password'" v-model="settings.tg_chat_id" class="form-input" placeholder="Telegram Chat ID (optional for WeChat)">
                    <button type="button" class="password-toggle" @click="togglePassword('tgChatId')">
                      {{ passwordVisible.tgChatId ? '🙈' : '👁️' }}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div class="settings-section">
              <div class="section-title"><span>▸</span> {{ trans.turnstileSettings }}</div>

              <div class="checkbox-item">
                <input type="checkbox" id="cfg_turnstile_enabled" v-model="settings.turnstile_enabled">
                <label><b>{{ trans.enableTurnstile }}</b></label>
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.turnstileSiteKey }}</label>
                <input type="text" v-model="settings.turnstile_site_key" class="form-input" :placeholder="trans.turnstileSiteKeyPlaceholder">
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.turnstileSecretKey }}</label>
                <div class="password-input-wrapper">
                  <input :type="passwordVisible.turnstileSecret ? 'text' : 'password'" v-model="settings.turnstile_secret_key" class="form-input" :placeholder="trans.turnstileSecretKeyPlaceholder">
                  <button type="button" class="password-toggle" @click="togglePassword('turnstileSecret')">
                    {{ passwordVisible.turnstileSecret ? '🙈' : '👁️' }}
                  </button>
                </div>
              </div>

              <p style="color: var(--text-muted); font-size: 12px; margin-top: 8px;">
                <span style="color: var(--accent-yellow);">[i]</span> 
                {{ trans.turnstileTip }}
              </p>
            </div>

            <div class="settings-section">
              <div class="section-title"><span>▸</span> {{ trans.adminLoginSettings }}</div>
              <p style="color: var(--text-muted); font-size: 12px; margin-bottom: 12px;">
                <span style="color: var(--accent-yellow);">[i]</span>
                {{ trans.adminLoginTip }}
              </p>

              <div class="form-group">
                <label class="form-label">{{ trans.username }}</label>
                <input type="text" v-model="settings.username" class="form-input" :placeholder="trans.usernamePlaceholder">
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.password }}</label>
                <div class="password-input-wrapper">
                  <input :type="passwordVisible.password ? 'text' : 'password'" v-model="settings.password" class="form-input" placeholder="••••••••">
                  <button type="button" class="password-toggle" @click="togglePassword('password')">
                    {{ passwordVisible.password ? '🙈' : '👁️' }}
                  </button>
                </div>
              </div>

              <div class="form-group">
                <label class="form-label">{{ trans.confirmPassword }}</label>
                <div class="password-input-wrapper">
                  <input :type="passwordVisible.confirmPassword ? 'text' : 'password'" v-model="settings.confirm_password" class="form-input" placeholder="••••••••">
                  <button type="button" class="password-toggle" @click="togglePassword('confirmPassword')">
                    {{ passwordVisible.confirmPassword ? '🙈' : '👁️' }}
                  </button>
                </div>
              </div>

              <p style="color: var(--text-muted); font-size: 12px; margin-top: 8px;">
                <span style="color: var(--accent-yellow);">[i]</span>
                {{ trans.apiSecretTip }}
              </p>
            </div>

            <div class="settings-section">
              <div class="section-title"><span>▸</span> {{ trans.jwtSettings }}</div>

              <div class="form-group">
                <label class="form-label">{{ trans.jwtSecret }}</label>
                <div class="password-input-wrapper">
                  <input :type="passwordVisible.jwtSecret ? 'text' : 'password'" v-model="settings.jwt_secret" class="form-input" :placeholder="trans.jwtSecretPlaceholder">
                  <button type="button" class="password-toggle" @click="togglePassword('jwtSecret')">
                    {{ passwordVisible.jwtSecret ? '🙈' : '👁️' }}
                  </button>
                </div>
              </div>

              <p style="color: var(--text-muted); font-size: 12px; margin-top: 8px;">
                <span style="color: var(--accent-yellow);">[i]</span> 
                {{ trans.jwtSecretTip }}
              </p>
            </div>
          </div>

          <div style="margin-top: 20px; text-align: right;">
            <button @click="saveSettings" class="btn btn-primary" :disabled="saving" style="padding: 12px 24px; font-size: 14px;">{{ saving ? '⏳' : '💾' }} {{ saving ? trans.saving : trans.saveConfig }}</button>
          </div>
        </div>

        <div id="tab-database" class="tab-content" :class="{ active: activeTab === 'database' }">
          <div class="settings-section">
            <div class="section-title"><span>▸</span> {{ trans.dbManagement }}</div>
            
            <div style="display: flex; gap: 20px;">
              <div class="form-group" style="flex: 1;">
                <label class="form-label">{{ trans.upgradeDatabase }}</label>
                <p style="color: var(--text-muted); margin-bottom: 8px;">{{ trans.upgradeDesc }}</p>
                <button @click="openDbModal('upgrade')" class="btn btn-primary" :disabled="dbLoading" style="padding: 12px 24px; font-size: 14px;">⬆️ {{ trans.upgradeDatabase }}</button>
              </div>

              <div class="form-group" style="flex: 1;">
                <label class="form-label" style="color: var(--accent-red); font-weight: 600;">⚠️ {{ trans.rebuildDatabase }}</label>
                <p style="color: var(--text-muted); margin-bottom: 8px;">{{ trans.rebuildDesc }}</p>
                <button @click="openDbModal('rebuild')" class="btn btn-red" :disabled="dbLoading" style="padding: 12px 24px; font-size: 14px;">🗑️ {{ trans.rebuildDatabase }}</button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div id="editModal" class="modal-overlay" :class="{ active: showEditModal }">
        <div class="modal-dialog">
          <div class="modal-header">
            <div class="modal-title">$ vim /etc/server.conf</div>
            <button class="modal-close" @click="closeEditModal">✕</button>
          </div>
          <input type="hidden" v-model="editForm.id">

          <div class="form-group">
            <label class="form-label">{{ trans.hostnameLabel }} <span class="required">*</span></label>
            <input type="text" v-model="editForm.name" class="form-input" placeholder="e.g. My Server">
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.groupName }}</label>
            <input type="text" v-model="editForm.server_group" class="form-input" placeholder="e.g. US VPS">
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.price }}</label>
            <input type="text" v-model="editForm.price" class="form-input" placeholder="e.g. $40/year">
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.expirationDate }}</label>
            <input type="date" v-model="editForm.expire_date" class="form-input">
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.bandwidth }}</label>
            <input type="text" v-model="editForm.bandwidth" class="form-input" placeholder="e.g. 1Gbps">
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.trafficLimit }}</label>
            <input type="text" v-model="editForm.traffic_limit" class="form-input" placeholder="e.g. 1TB/month">
          </div>

          <div class="form-group">
            <div class="checkbox-item" style="margin:0;">
              <input type="checkbox" v-model="editForm.is_hidden">
              <label>
                <b>{{ trans.hideFromPublic }}</b><br>
                <span style="font-size:10px;color:var(--text-muted);">{{ trans.hideDesc }}</span>
              </label>
            </div>
          </div>

          <div class="modal-footer">
            <button @click="closeEditModal" class="btn">{{ trans.cancel }}</button>
            <button @click="saveEdit" class="btn btn-primary">{{ trans.save }}</button>
          </div>
        </div>
      </div>

      <div id="deleteModal" class="modal-overlay" :class="{ active: showDeleteModal }">
        <div class="modal-dialog">
          <div class="modal-header">
            <div class="modal-title">$ rm -rf /etc/server.conf</div>
            <button class="modal-close" @click="closeDeleteModal">✕</button>
          </div>
          <input type="hidden" v-model="deleteServerId">

          <div style="margin-bottom: 16px;">
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
              <span style="color: var(--accent-red); font-size: 20px;">⚠️</span>
              <span style="color: var(--accent-red); font-weight: 600;">{{ trans.dangerWarning }}</span>
            </div>
            <p style="color: var(--text-secondary); font-size: 12px; line-height: 1.6;">
              {{ trans.deleteConfirm }}
              <br><br>
              <strong style="color: var(--text-primary);">{{ trans.recommendUninstall }}：</strong>
            </p>
          </div>

          <div class="cmd-input-wrapper" :class="{ copied: uninstallCopied }" style="margin-bottom: 12px;">
            <span class="cmd-prompt">$</span>
            <input type="text" readonly :value="getUninstallCommand()" class="cmd-input" style="flex: 1;">
            <button @click="copyUninstallCmd" class="btn btn-icon btn-green" :title="trans.copy" style="margin-left: 8px;">{{ uninstallCopied ? '✅' : '📋' }}</button>
          </div>

          <p style="color: var(--text-muted); margin-bottom: 16px;">
            <span style="color: var(--accent-yellow);">[i]</span> {{ trans.clickToCopyCmd }}
          </p>

          <div class="modal-footer" style="justify-content: space-between;">
            <button @click="confirmDelete" class="btn btn-red">{{ trans.confirmDelete }}</button>
            <button @click="closeDeleteModal" class="btn">{{ trans.cancelAction }}</button>
          </div>
        </div>
      </div>

      <div id="copyModal" class="modal-overlay" :class="{ active: showCopyModal }">
        <div class="modal-dialog">
          <div class="modal-header">
            <div class="modal-title">bash -s install</div>
            <button class="modal-close" @click="closeCopyModal">✕</button>
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.targetOs }}</label>
            <select v-model="targetOs" class="form-select">
              <option value="linux">Linux (Ubuntu/Debian/CentOS)</option>
              <option value="alpine">Alpine Linux</option>
              <option value="windows">Windows</option>
            </select>
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.reportInterval }}</label>
            <select v-model="reportInterval" class="form-select">
              <option :value="60">60</option>
              <option :value="120">120</option>
              <option :value="180">180</option>
            </select>
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.pingMode }}</label>
            <select v-model="pingMode" class="form-select">
              <option value="http">HTTP</option>
              <option value="tcp">TCP</option>
            </select>
            <p style="color: var(--text-muted); margin-top: 8px;">
              <span style="color: var(--accent-yellow);">[i]</span> {{ trans.tcpWarning }}
            </p>
          </div>

          <div class="form-group">
            <label class="form-label">{{ trans.installCommand }}</label>
            <div class="cmd-input-wrapper" :class="{ copied: copiedCmd }">
              <span class="cmd-prompt">$</span>
              <input type="text" readonly :value="getCustomInstallCommand()" class="cmd-input" style="flex: 1;">
            </div>
          </div>

          <div class="modal-footer" style="justify-content: flex-end;">
            <button @click="copyCustomCmd" class="btn btn-primary">{{ copiedCmd ? '✅ ' + trans.copied : '📋 ' + trans.copy }}</button>
            <button @click="closeCopyModal" class="btn">{{ trans.close }}</button>
          </div>
        </div>
      </div>

      <div id="dbModal" class="modal-overlay" :class="{ active: showDbModal }">
        <div class="modal-dialog">
          <div class="modal-header">
            <div class="modal-title">$ {{ dbOperation === 'rebuild' ? 'DROP DATABASE' : 'ALTER DATABASE' }}</div>
            <button class="modal-close" @click="closeDbModal" :disabled="dbLoading">✕</button>
          </div>

          <div v-if="dbOperation === 'rebuild'" style="margin-bottom: 16px;">
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
              <span style="color: var(--accent-red); font-size: 20px;">⚠️</span>
              <span style="color: var(--accent-red); font-weight: 600;">{{ trans.dangerOperation }}</span>
            </div>
            <p style="color: var(--text-secondary); font-size: 12px; line-height: 1.6;">
              {{ trans.rebuildWarning }}
            </p>
          </div>

          <div v-if="dbOperation === 'upgrade'" style="margin-bottom: 16px;">
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
              <span style="color: var(--accent-yellow); font-size: 20px;">ℹ️</span>
              <span style="color: var(--accent-yellow); font-weight: 600;">{{ trans.upgradeDatabase }}</span>
            </div>
            <p style="color: var(--text-secondary); font-size: 12px; line-height: 1.6;">
              {{ trans.upgradeDesc }}
            </p>
          </div>

          <div v-if="dbResult" :style="{ padding: '12px', borderRadius: '4px', marginBottom: '16px', background: dbResult.success ? 'rgba(46,160,67,0.1)' : 'rgba(248,81,73,0.1)', border: '1px solid ' + (dbResult.success ? 'var(--accent-green)' : 'var(--accent-red)') }">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span :style="{ color: dbResult.success ? 'var(--accent-green)' : 'var(--accent-red)', fontWeight: '600' }">
                {{ dbResult.success ? '✅' : '❌' }} {{ getMessage(dbResult.message) || (dbResult.success ? trans.operationSuccess : trans.operationFailed) }}
              </span>
            </div>
            <div v-if="dbResult.error" style="color: var(--accent-red); margin-top: 8px;">
              {{ dbResult.error }}
            </div>
          </div>

          <div class="modal-footer" style="justify-content: space-between;">
            <button 
              v-if="!dbResult" 
              @click="dbOperation === 'rebuild' ? handleRebuildDatabase() : handleUpgradeDatabase()" 
              class="btn btn-red" 
              :disabled="dbLoading"
            >
              {{ dbLoading ? (dbOperation === 'rebuild' ? trans.rebuilding : trans.upgrading) : (dbOperation === 'rebuild' ? trans.confirmRebuild : trans.upgradeDatabase) }}
            </button>
            <button @click="closeDbModal" class="btn" :disabled="dbLoading">{{ trans.cancel }}</button>
          </div>
        </div>
      </div>

      <Footer />
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import TerminalHeader from '../components/TerminalHeader.vue'
import Footer from '../components/Footer.vue'
import { adminApi, login, logout as apiLogout, formatBytes, upgradeDatabase, rebuildDatabase } from '../utils/api'
import { t, currentLang } from '../utils/i18n'
import { translations } from '../utils/i18n'

const API_BASE = window.location.origin

const trans = computed(() => translations[currentLang.value] || translations.en)

const getMessage = (msg) => {
  if (typeof msg === 'string') return msg
  if (typeof msg === 'object' && msg !== null) {
    return msg[currentLang.value] || msg.en || Object.values(msg)[0] || ''
  }
  return ''
}

const isLoggedIn = ref(false)
const loginForm = ref({ username: '', password: '' })
const loginError = ref('')
const loginLoading = ref(false)
const turnstileEnabled = ref(false)
const turnstileSiteKey = ref('')
const turnstileToken = ref('')
const activeTab = ref('servers')
const servers = ref([])
const selectedServers = ref([])
const stats = ref({ total: '-', online: 0, offline: 0, avg_cpu: 0 })
const groups = ref(['Default'])
const newServerName = ref('')
const newServerGroup = ref('Default')

const settings = ref({
  site_title: '',
  admin_title: '',
  custom_bg: '',
  custom_head: '',
  custom_script: '',
  is_public: false,
  show_price: true,
  show_expire: true,
  show_bw: true,
  show_tf: true,
  tg_notify: 'false',
  tg_bot_token: '',
  tg_chat_id: '',
  turnstile_enabled: false,
  turnstile_site_key: '',
  turnstile_secret_key: '',
  jwt_secret: '',
  username: '',
  password: '',
  confirm_password: ''
})
const apiSecret = ref('')

const passwordVisible = ref({
  login: false,
  tgBotToken: false,
  tgChatId: false,
  turnstileSecret: false,
  jwtSecret: false,
  username: false,
  password: false,
  confirmPassword: false
})

const togglePassword = (field) => {
  passwordVisible.value[field] = !passwordVisible.value[field]
}

const showEditModal = ref(false)
const editForm = ref({
  id: '',
  name: '',
  server_group: '',
  price: '',
  expire_date: '',
  bandwidth: '',
  traffic_limit: '',
  is_hidden: false
})

const showDeleteModal = ref(false)
const deleteServerId = ref('')

const copiedServerId = ref(null)
const uninstallCopied = ref(false)
const saving = ref(false)

const showDbModal = ref(false)
const dbOperation = ref('')
const dbLoading = ref(false)
const dbResult = ref(null)

const showCopyModal = ref(false)
const copyServerId = ref('')
const targetOs = ref('linux')
const reportInterval = ref(60)
const pingMode = ref('http')
const copiedCmd = ref(false)

const handleLogin = async () => {
    loginError.value = ''
    loginLoading.value = true
    
    if (turnstileEnabled.value && !turnstileToken.value) {
      loginError.value = 'Please complete the verification'
      loginLoading.value = false
      return
    }
    
    const res = await login(loginForm.value.username, loginForm.value.password, turnstileToken.value)
    if (res.ok) {
      isLoggedIn.value = true
      if (turnstileToken.value) {
        localStorage.setItem('turnstile_token', turnstileToken.value)
      }
      loadSettings()
      loadServers()
      refreshStats()
    } else {
      loginError.value = trans.value.errorInvalidUsername
      loginForm.value.password = ''
      turnstileToken.value = ''
      localStorage.removeItem('turnstile_token')
      if (window.turnstile) {
        window.turnstile.reset('#admin-turnstile-container')
      }
    }
    loginLoading.value = false
  }

const logout = () => {
  apiLogout()
  isLoggedIn.value = false
  localStorage.removeItem('turnstile_token')
}

const checkLoginStatus = () => {
  const token = localStorage.getItem('jwt_token')
  return !!token
}

const initAdmin = async () => {
  const hasCreds = checkLoginStatus()
  if (hasCreds) {
    isLoggedIn.value = true
    const savedTurnstileToken = localStorage.getItem('turnstile_token')
    if (savedTurnstileToken) {
      turnstileToken.value = savedTurnstileToken
    }
    loadSettings()
    loadServers()
    refreshStats()
  } else {
    await loadTurnstileConfig()
  }
}

const loadTurnstileConfig = async () => {
  try {
    const res = await fetch(`${API_BASE}/api/config`)
    if (res.ok) {
      const config = await res.json()
      turnstileEnabled.value = config.turnstile_enabled === true || config.turnstile_enabled === 'true'
      turnstileSiteKey.value = config.turnstile_site_key || ''
      
      if (turnstileEnabled.value && turnstileSiteKey.value) {
        await loadTurnstileScript()
        renderTurnstile()
      }
    }
  } catch (e) {
    console.error('Failed to load Turnstile config:', e)
  }
}

const loadTurnstileScript = () => {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js'
    script.async = true
    script.onload = resolve
    script.onerror = reject
    document.head.appendChild(script)
  })
}

const renderTurnstile = () => {
  if (window.turnstile) {
    window.turnstile.render('#admin-turnstile-container', {
      sitekey: turnstileSiteKey.value,
      callback: (token) => {
        turnstileToken.value = token
        localStorage.setItem('turnstile_token', token)
      },
      errorCallback: () => {
        turnstileToken.value = ''
        localStorage.removeItem('turnstile_token')
      },
      expiredCallback: () => {
        turnstileToken.value = ''
        localStorage.removeItem('turnstile_token')
      }
    })
  }
}

const loadSettings = async () => {
  try {
    const res = await adminApi({ action: 'get_settings' })
    if (res.ok) {
      const data = await res.json()
      const settingsData = data.settings || {}
      settings.value = {
        site_title: settingsData.site_title || '',
        admin_title: settingsData.admin_title || '',
        custom_bg: settingsData.custom_bg || '',
        custom_head: settingsData.custom_head || '',
        custom_script: settingsData.custom_script || '',
        is_public: settingsData.is_public === 'true',
        show_price: settingsData.show_price === 'true',
        show_expire: settingsData.show_expire === 'true',
        show_bw: settingsData.show_bw === 'true',
        show_tf: settingsData.show_tf === 'true',
        tg_notify: settingsData.tg_notify || 'false',
        tg_bot_token: settingsData.tg_bot_token || '',
        tg_chat_id: settingsData.tg_chat_id || '',
        turnstile_enabled: settingsData.turnstile_enabled === 'true',
        turnstile_site_key: settingsData.turnstile_site_key || '',
        turnstile_secret_key: settingsData.turnstile_secret_key || '',
        jwt_secret: settingsData.jwt_secret || '',
        username: settingsData.username || '',
        password: ''  // 不显示加密后的密码
      }
      apiSecret.value = data.api_secret || ''
    }
  } catch (e) {
    console.error('[ERROR] Load settings failed:', e)
  }
}

const saveSettings = async () => {
    if (saving.value) return

    const jwtSecret = settings.value.jwt_secret
    if (jwtSecret && jwtSecret.length > 0 && jwtSecret.length < 32) {
      alert(trans.jwtSecretMinLength)
      return
    }

    if (jwtSecret && /\s/.test(jwtSecret)) {
      alert(trans.jwtSecretNoWhitespace)
      return
    }

    if (!settings.value.username || settings.value.username.trim().length === 0) {
      alert(trans.value.usernameRequired)
      return
    }

    // 只有当用户输入了新密码时才验证密码确认
    if (settings.value.password && settings.value.password.length > 0) {
      if (settings.value.password !== settings.value.confirm_password) {
        alert(trans.value.passwordMismatch)
        return
      }
    }

    saving.value = true

    const data = {
      action: 'save_settings',
      settings: {
        site_title: settings.value.site_title,
        admin_title: settings.value.admin_title,
        custom_bg: settings.value.custom_bg,
        custom_head: settings.value.custom_head,
        custom_script: settings.value.custom_script,
        is_public: settings.value.is_public ? 'true' : 'false',
        show_price: settings.value.show_price ? 'true' : 'false',
        show_expire: settings.value.show_expire ? 'true' : 'false',
        show_bw: settings.value.show_bw ? 'true' : 'false',
        show_tf: settings.value.show_tf ? 'true' : 'false',
        tg_notify: settings.value.tg_notify,
        tg_bot_token: settings.value.tg_bot_token,
        tg_chat_id: settings.value.tg_chat_id,
        turnstile_enabled: settings.value.turnstile_enabled ? 'true' : 'false',
        turnstile_site_key: settings.value.turnstile_site_key,
        turnstile_secret_key: settings.value.turnstile_secret_key,
        jwt_secret: settings.value.jwt_secret,
        username: settings.value.username
      }
    }

    // 只有当用户输入了新密码时才保存密码
    if (settings.value.password && settings.value.password.length > 0) {
      data.settings.password = settings.value.password
    }

    try {
      const res = await adminApi(data)
      const result = await res.json()
      if (res.ok) {
        alert(getMessage(result.message) || 'Success')
        location.reload()
      } else {
        alert(result.error || 'Fail')
      }
    } catch (e) {
      alert('Fail: ' + e.message)
    } finally {
      saving.value = false
    }
  }

  const loadServers = async () => {
    try {
      const res = await adminApi({ action: 'list' })
      if (res.ok) {
        const data = await res.json()
        servers.value = data.servers || []
        
        const serverGroups = [...new Set(servers.value.map(s => s.server_group || trans.value.default))]
        groups.value = serverGroups
      }
    } catch (e) {
      console.error('[ERROR] Load servers failed:', e)
    }
  }

const refreshStats = async () => {
  try {
    const res = await adminApi({ action: 'get_stats' })
    if (res.ok) {
      const data = await res.json()
      stats.value = data.stats || { total: '-', online: 0, offline: 0, avg_cpu: 0 }
    }
  } catch (e) {
    console.error('[ERROR] Refresh stats failed:', e)
  }
}

const addServer = async () => {
    const name = newServerName.value.trim()
    if (!name) return alert(trans.value.enterServerName)

    try {
      const res = await adminApi({ action: 'add', name })
      const result = await res.json()
      if (res.ok) {
        alert(getMessage(result.message) || 'Success')
        location.reload()
      } else {
        alert(result.error || 'Fail')
      }
    } catch (e) {
      alert('Fail: ' + e.message)
    }
  }

const getInstallCommand = (serverId) => {
  const HOST = API_BASE
  return `curl -sL ${HOST}/install.sh | bash -s install ${serverId} ${apiSecret.value} ${HOST}/update 60 http`
}

const getUninstallCommand = () => {
  return `curl -sL ${API_BASE}/install.sh | bash -s uninstall`
}

const copyCmd = (serverId) => {
  copyServerId.value = serverId
  targetOs.value = 'linux'
  reportInterval.value = 60
  pingMode.value = 'http'
  copiedCmd.value = false
  showCopyModal.value = true
}

const getCustomInstallCommand = () => {
  const HOST = API_BASE
  if (targetOs.value === 'windows') {
    return `${HOST}/cf-server-monitor.pyw`
  }
  const shell = targetOs.value === 'alpine' ? 'sh' : 'bash'
  const script = targetOs.value === 'alpine' ? 'install-alpine.sh' : 'install.sh'
  return `curl -sL ${HOST}/${script} | ${shell} -s install ${copyServerId.value} ${apiSecret.value} ${HOST}/update ${reportInterval.value} ${pingMode.value}`
}

const copyCustomCmd = async () => {
  const cmd = getCustomInstallCommand()
  try {
    await navigator.clipboard.writeText(cmd)
  } catch (e) {
    document.execCommand('copy')
  }

  copiedCmd.value = true
  setTimeout(() => {
    copiedCmd.value = false
  }, 1500)
}

const closeCopyModal = () => {
  showCopyModal.value = false
}

const copyUninstallCmd = async () => {
  const cmd = getUninstallCommand()
  try {
    await navigator.clipboard.writeText(cmd)
  } catch (e) {
    document.execCommand('copy')
  }

  uninstallCopied.value = true
  setTimeout(() => {
    uninstallCopied.value = false
  }, 1500)
}

const openEditModal = (server) => {
  editForm.value = {
    id: server.id,
    name: server.name || '',
    server_group: server.server_group || '',
    price: server.price || '',
    expire_date: server.expire_date || '',
    bandwidth: server.bandwidth || '',
    traffic_limit: server.traffic_limit || '',
    is_hidden: server.is_hidden === '1'
  }
  showEditModal.value = true
}

const closeEditModal = () => {
  showEditModal.value = false
}

const saveEdit = async () => {
    const data = {
      action: 'edit',
      id: editForm.value.id,
      name: editForm.value.name,
      server_group: editForm.value.server_group,
      price: editForm.value.price,
      expire_date: editForm.value.expire_date,
      bandwidth: editForm.value.bandwidth,
      traffic_limit: editForm.value.traffic_limit,
      is_hidden: editForm.value.is_hidden ? '1' : '0'
    }

    try {
      const res = await adminApi(data)
      const result = await res.json()
      if (res.ok) {
        alert(getMessage(result.message) || 'Success')
        location.reload()
      } else {
        alert(result.error || 'Fail')
      }
    } catch (e) {
      alert('Fail: ' + e.message)
    }
  }

  const openDeleteModal = (id) => {
    deleteServerId.value = id
    showDeleteModal.value = true
  }

  const closeDeleteModal = () => {
    showDeleteModal.value = false
  }

  const confirmDelete = async () => {
    try {
      const res = await adminApi({ action: 'delete', id: deleteServerId.value })
      const result = await res.json()
      if (res.ok) {
        alert(getMessage(result.message) || 'Success')
        location.reload()
      } else {
        alert(result.error || 'Fail')
      }
    } catch (e) {
      alert('Fail: ' + e.message)
    }
  }

  const batchDelete = async () => {
    if (selectedServers.value.length === 0) return alert(trans.value.selectServers)
    if (!confirm(trans.value.confirmDeleteServers + selectedServers.value.length + trans.value.irreversible)) return

    try {
      const res = await adminApi({ action: 'batch_delete', ids: selectedServers.value })
      const result = await res.json()
      if (res.ok) {
        alert(getMessage(result.message) || 'Success')
        location.reload()
      } else {
        alert(result.error || 'Fail')
      }
    } catch (e) {
      alert('Fail: ' + e.message)
    }
  }

const handleSelectAll = (e) => {
  const checked = e.target.checked
  selectedServers.value = checked ? servers.value.map(s => s.id) : []
}

const toggleSelectAll = () => {
  if (selectedServers.value.length === servers.value.length) {
    selectedServers.value = []
  } else {
    selectedServers.value = servers.value.map(s => s.id)
  }
}

const getStatusColor = (server) => {
  return server.is_online ? 'var(--accent-green)' : 'var(--accent-red)'
}

const getStatusText = (server) => {
  let status = server.is_online ? '● ' + trans.value.online : '● ' + trans.value.offline
  return status.toUpperCase()
}

  let draggedRow = null

  const handleDragStart = (e) => {
    const row = e.target.closest('.server-row')
    draggedRow = row ? row.dataset.serverId : null
    e.dataTransfer.effectAllowed = 'move'
  }

  const handleDrop = async (e, targetId) => {
    if (!draggedRow || draggedRow === targetId) return
    
    const rows = Array.from(document.querySelectorAll('.server-row'))
    const draggedIndex = rows.findIndex(r => r.dataset.serverId === draggedRow)
    const targetIndex = rows.findIndex(r => r.dataset.serverId === targetId)
    
    const orders = rows.map(r => r.dataset.serverId)
    const [dragged] = orders.splice(draggedIndex, 1)
    orders.splice(targetIndex, 0, dragged)
    
    try {
      const res = await adminApi({ action: 'save_order', orders })
      if (res.ok) {
        loadServers()
      }
    } catch (e) {
      console.error('[ERROR] Save order failed:', e)
    }
    
    draggedRow = null
  }

  const uploadBg = (e) => {
    const file = e.target.files[0]
    if (!file) return
    if (file.size > 800 * 1024) {
      alert(trans.value.imageSizeWarning)
    }
    const reader = new FileReader()
    reader.onload = function(event) {
      settings.value.custom_bg = event.target.result
    }
    reader.readAsDataURL(file)
  }

const handleUpgradeDatabase = async () => {
  dbOperation.value = 'upgrade'
  dbLoading.value = true
  dbResult.value = null
  
  try {
    const result = await upgradeDatabase()
    dbResult.value = result
    if (result.success) {
      setTimeout(() => {
        showDbModal.value = false
        location.reload()
      }, 1500)
    }
  } catch (e) {
    dbResult.value = { success: false, error: e.message }
  } finally {
    dbLoading.value = false
  }
}

const handleRebuildDatabase = async () => {
  dbOperation.value = 'rebuild'
  dbLoading.value = true
  dbResult.value = null
  
  try {
    const result = await rebuildDatabase()
    dbResult.value = result
    if (result.success) {
      setTimeout(() => {
        showDbModal.value = false
        location.reload()
      }, 1500)
    }
  } catch (e) {
    dbResult.value = { success: false, error: e.message }
  } finally {
    dbLoading.value = false
  }
}

const openDbModal = (operation) => {
  dbOperation.value = operation
  dbResult.value = null
  showDbModal.value = true
}

const closeDbModal = () => {
  if (!dbLoading.value) {
    showDbModal.value = false
  }
}

onMounted(() => {
  initAdmin()
})
</script>