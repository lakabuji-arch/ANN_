<template>
  <div class="index-manager">
    <div class="info">
      <div class="row"><span>Active Zone:</span><strong>{{ status.active_zone || 'A' }}</strong></div>
      <div class="row"><span>Total Vectors:</span><strong>{{ (status.total_vectors || 0).toLocaleString() }}</strong></div>
      <div class="row"><span>Clusters:</span><strong>{{ status.num_clusters || 0 }}</strong></div>
      <div class="row"><span>DDR4 Used:</span><strong>{{ status.ddr4_used_mb || 0 }} MB</strong></div>
    </div>
    <button @click="$emit('reindex')">Trigger Reindex</button>
  </div>
</template>

<script setup>
defineProps({ status: Object })
defineEmits(['reindex'])
</script>

<style scoped>
.info { margin-bottom: 20px; }
.row { display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #1e293b; }
.row span { color: #64748b; }
.row strong { color: #e2e8f0; }
button { padding: 12px 32px; background: #3b82f6; color: white; border: none; border-radius: 8px; cursor: pointer; font-size: 16px; }
button:hover { background: #2563eb; }
</style>
