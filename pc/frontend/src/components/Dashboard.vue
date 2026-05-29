<template>
  <div class="dashboard">
    <div class="cards">
      <div class="card"><div class="label">QPS</div><div class="value">{{ status.qps || 0 }}</div></div>
      <div class="card"><div class="label">Avg Latency</div><div class="value">{{ (status.avg_latency_us || 0).toLocaleString() }} μs</div></div>
      <div class="card"><div class="label">P99 Latency</div><div class="value">{{ (status.p99_latency_us || 0).toLocaleString() }} μs</div></div>
      <div class="card"><div class="label">DDR4 Used</div><div class="value">{{ status.ddr4_used_mb || 0 }} MB</div></div>
      <div class="card"><div class="label">Total Vectors</div><div class="value">{{ (status.total_vectors || 0).toLocaleString() }}</div></div>
      <div class="card"><div class="label">Temperature</div><div class="value">{{ status.temperature || 0 }} °C</div></div>
    </div>
    <v-chart :option="latencyOption" style="height:350px" />
  </div>
</template>

<script setup>
import { computed } from 'vue'
import VChart from 'vue-echarts'
import 'echarts'

const props = defineProps({ status: Object, latencyHistory: Array })

const latencyOption = computed(() => ({
  title: { text: 'Search Latency (Real-time)', textStyle: { color: '#e2e8f0' } },
  tooltip: { trigger: 'axis' },
  xAxis: { type: 'category', show: false },
  yAxis: { type: 'value', name: 'μs' },
  series: [{
    data: props.latencyHistory || [],
    type: 'line',
    smooth: true,
    areaStyle: { opacity: 0.2, color: '#3b82f6' },
    lineStyle: { color: '#3b82f6' },
    showSymbol: false,
  }],
  grid: { top: 40, right: 20, bottom: 30, left: 60 },
  backgroundColor: 'transparent',
}))
</script>

<style scoped>
.cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px; }
.card { background: #0f172a; border-radius: 8px; padding: 20px; text-align: center; }
.label { font-size: 12px; color: #64748b; text-transform: uppercase; margin-bottom: 8px; }
.value { font-size: 28px; font-weight: 700; color: #3b82f6; }
</style>
