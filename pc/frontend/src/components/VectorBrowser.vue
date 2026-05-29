<template>
  <div class="browser">
    <div class="search-bar">
      <input v-model="queryStr" placeholder="Enter query vector, comma-separated (e.g. 0.1,0.2,...)" @keyup.enter="doSearch" />
      <select v-model="topk"><option v-for="v in [1,5,10,20,50]" :key="v" :value="v">Top-{{ v }}</option></select>
      <select v-model="metric"><option value="L2">L2</option><option value="COSINE">Cosine</option><option value="IP">IP</option></select>
      <button @click="doSearch">Search</button>
    </div>
    <div v-if="results.length" class="results">
      <p class="latency">{{ latency.toFixed(1) }} μs</p>
      <table>
        <tr><th>Rank</th><th>Distance</th><th>Vector ID</th></tr>
        <tr v-for="(r, i) in results" :key="i">
          <td>{{ i + 1 }}</td>
          <td>{{ r.distance.toFixed(6) }}</td>
          <td>{{ r.vector_id }}</td>
        </tr>
      </table>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'

const props = defineProps({ results: Array, latency: Number })
const emit = defineEmits(['search'])

const queryStr = ref('')
const topk = ref(10)
const metric = ref('L2')

function doSearch() {
  const vec = queryStr.value.split(',').map(Number)
  if (vec.length > 0) emit('search', vec, topk.value, metric.value, 2)
}
</script>

<style scoped>
.search-bar { display: flex; gap: 8px; margin-bottom: 16px; }
.search-bar input { flex: 1; padding: 10px; background: #0f172a; border: 1px solid #334155; border-radius: 6px; color: #e2e8f0; }
.search-bar select, .search-bar button { padding: 10px; background: #0f172a; border: 1px solid #334155; border-radius: 6px; color: #e2e8f0; cursor: pointer; }
.search-bar button { background: #3b82f6; border-color: #3b82f6; }
.latency { color: #22c55e; margin-bottom: 12px; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #334155; }
</style>
