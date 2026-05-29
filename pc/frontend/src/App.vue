<template>
  <div class="app">
    <header class="header">
      <h1>Vector Search Appliance</h1>
      <span class="status-dot" :class="{ connected: fpgaConnected }"></span>
      <span class="status-text">{{ fpgaConnected ? 'FPGA Connected' : 'FPGA Offline' }}</span>
    </header>

    <nav class="tabs">
      <button v-for="t in tabs" :key="t.id" :class="{ active: activeTab === t.id }" @click="activeTab = t.id">
        {{ t.label }}
      </button>
    </nav>

    <main class="content">
      <Dashboard v-if="activeTab === 'dashboard'" :status="status" :latencyHistory="latencyHistory" />
      <VectorBrowser v-if="activeTab === 'browser'" @search="doSearch" :results="searchResults" :latency="searchLatency" />
      <IndexManager v-if="activeTab === 'index'" :status="status" @reindex="doReindex" />
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import axios from 'axios'
import Dashboard from './components/Dashboard.vue'
import VectorBrowser from './components/VectorBrowser.vue'
import IndexManager from './components/IndexManager.vue'

const fpgaConnected = ref(false)
const activeTab = ref('dashboard')
const tabs = [
  { id: 'dashboard', label: 'Dashboard' },
  { id: 'browser', label: 'Vector Browser' },
  { id: 'index', label: 'Index Manager' },
]

const status = ref({})
const latencyHistory = ref([])
const searchResults = ref([])
const searchLatency = ref(0)
let pollTimer = null

async function pollStatus() {
  try {
    const { data } = await axios.get('/api/status')
    status.value = data
    fpgaConnected.value = true
    latencyHistory.value.push(data.avg_latency_us)
    if (latencyHistory.value.length > 100) latencyHistory.value.shift()
  } catch {
    fpgaConnected.value = false
  }
}

async function doSearch(query, topk, metric, probes) {
  const { data } = await axios.post('/api/search', { vector: query, topk, metric, probes })
  searchResults.value = data.results
  searchLatency.value = data.latency_us
}

async function doReindex() {
  await axios.post('/api/reindex')
  alert('Reindex triggered. Check dashboard for progress.')
}

onMounted(() => {
  pollTimer = setInterval(pollStatus, 1000)
})

onUnmounted(() => clearInterval(pollTimer))
</script>

<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', system-ui, sans-serif; background: #0f172a; color: #e2e8f0; }
.app { max-width: 1200px; margin: 0 auto; padding: 20px; }
.header { display: flex; align-items: center; gap: 12px; margin-bottom: 20px; }
.header h1 { font-size: 24px; }
.status-dot { width: 12px; height: 12px; border-radius: 50%; background: #ef4444; }
.status-dot.connected { background: #22c55e; }
.status-text { font-size: 14px; color: #94a3b8; }
.tabs { display: flex; gap: 2px; margin-bottom: 24px; background: #1e293b; border-radius: 8px; padding: 4px; }
.tabs button { flex: 1; padding: 10px; border: none; background: transparent; color: #94a3b8; border-radius: 6px; cursor: pointer; font-size: 14px; }
.tabs button.active { background: #3b82f6; color: white; }
.content { background: #1e293b; border-radius: 12px; padding: 24px; }
</style>
