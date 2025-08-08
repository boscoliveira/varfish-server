<script setup>
import { computed } from 'vue'

import { useVariantQueryStore } from '@/variants/stores/variantQuery'

const props = defineProps({
  querySettings: { type: Object, required: true },
})

const variantQueryStore = useVariantQueryStore()

const effects = computed(() => props.querySettings?.effects ?? [])
const hpoTerms = computed(() => props.querySettings?.prio_hpo_terms ?? [])
const genes = computed(() => props.querySettings?.gene_allowlist ?? [])
const regions = computed(() => props.querySettings?.genomic_region ?? [])
const db = computed(() => props.querySettings?.database ?? null)

// Frequency chips: show if enabled and threshold set
const freqSources = [
  {
    key: 'gnomad_exomes',
    label: 'gnomAD exomes',
    enabled: () => props.querySettings?.gnomad_exomes_enabled,
    value: () => props.querySettings?.gnomad_exomes_frequency,
    clear: () => {
      props.querySettings.gnomad_exomes_enabled = false
      props.querySettings.gnomad_exomes_frequency = null
    },
  },
  {
    key: 'gnomad_genomes',
    label: 'gnomAD genomes',
    enabled: () => props.querySettings?.gnomad_genomes_enabled,
    value: () => props.querySettings?.gnomad_genomes_frequency,
    clear: () => {
      props.querySettings.gnomad_genomes_enabled = false
      props.querySettings.gnomad_genomes_frequency = null
    },
  },
  {
    key: 'thousand_genomes',
    label: '1000G',
    enabled: () => props.querySettings?.thousand_genomes_enabled,
    value: () => props.querySettings?.thousand_genomes_frequency,
    clear: () => {
      props.querySettings.thousand_genomes_enabled = false
      props.querySettings.thousand_genomes_frequency = null
    },
  },
  {
    key: 'exac',
    label: 'ExAC',
    enabled: () => props.querySettings?.exac_enabled,
    value: () => props.querySettings?.exac_frequency,
    clear: () => {
      props.querySettings.exac_enabled = false
      props.querySettings.exac_frequency = null
    },
  },
]

const clinvarChips = computed(() => {
  const chips = []
  if (props.querySettings?.require_in_clinvar) {
    chips.push({ key: 'require_in_clinvar', label: 'ClinVar only', clear: () => (props.querySettings.require_in_clinvar = false) })
  }
  const flags = [
    ['clinvar_include_pathogenic', 'ClinVar P'],
    ['clinvar_include_likely_pathogenic', 'ClinVar LP'],
    ['clinvar_include_uncertain_significance', 'ClinVar VUS'],
    ['clinvar_include_likely_benign', 'ClinVar LB'],
    ['clinvar_include_benign', 'ClinVar B'],
  ]
  for (const [key, label] of flags) {
    if (props.querySettings?.[key]) {
      chips.push({ key, label, clear: () => (props.querySettings[key] = false) })
    }
  }
  return chips
})

const removeEffect = (id) => {
  if (!props.querySettings?.effects) return
  props.querySettings.effects = props.querySettings.effects.filter((x) => x !== id)
}

const removeHpo = (term) => {
  if (!props.querySettings?.prio_hpo_terms) return
  props.querySettings.prio_hpo_terms = props.querySettings.prio_hpo_terms.filter((x) => x !== term)
}

const removeGene = (symbol) => {
  if (!props.querySettings?.gene_allowlist) return
  props.querySettings.gene_allowlist = props.querySettings.gene_allowlist.filter((x) => x !== symbol)
}

const removeRegion = (region) => {
  if (!props.querySettings?.genomic_region) return
  props.querySettings.genomic_region = props.querySettings.genomic_region.filter((x) => x !== region)
}

const clearDb = () => {
  props.querySettings.database = 'refseq'
}

</script>

<template>
  <div class="mb-2">
    <div class="d-flex flex-wrap gap-1 align-items-center">
      <template v-for="effect in effects" :key="`eff-${effect}`">
        <span class="badge badge-info mr-1 mb-1">
          {{ effect }}
          <button class="btn btn-link btn-sm p-0 ml-1" title="Remove" @click="removeEffect(effect)">
            <i-mdi-close />
          </button>
        </span>
      </template>

      <template v-for="term in hpoTerms" :key="`hpo-${term}`">
        <span class="badge badge-warning mr-1 mb-1">
          {{ term }}
          <button class="btn btn-link btn-sm p-0 ml-1" title="Remove" @click="removeHpo(term)">
            <i-mdi-close />
          </button>
        </span>
      </template>

      <template v-for="gene in genes" :key="`gene-${gene}`">
        <span class="badge badge-primary mr-1 mb-1">
          {{ gene }}
          <button class="btn btn-link btn-sm p-0 ml-1" title="Remove" @click="removeGene(gene)">
            <i-mdi-close />
          </button>
        </span>
      </template>

      <template v-for="region in regions" :key="`reg-${region}`">
        <span class="badge badge-secondary mr-1 mb-1">
          {{ region }}
          <button class="btn btn-link btn-sm p-0 ml-1" title="Remove" @click="removeRegion(region)">
            <i-mdi-close />
          </button>
        </span>
      </template>

      <template v-for="src in freqSources" :key="`freq-${src.key}`">
        <span v-if="src.enabled() && src.value() != null" class="badge badge-light mr-1 mb-1">
          AF ≤ {{ src.value() }} ({{ src.label }})
          <button class="btn btn-link btn-sm p-0 ml-1" title="Remove" @click="src.clear()">
            <i-mdi-close />
          </button>
        </span>
      </template>

      <template v-for="chip in clinvarChips" :key="`clinvar-${chip.key}`">
        <span class="badge badge-success mr-1 mb-1">
          {{ chip.label }}
          <button class="btn btn-link btn-sm p-0 ml-1" title="Remove" @click="chip.clear()">
            <i-mdi-close />
          </button>
        </span>
      </template>

      <span v-if="db" class="badge badge-dark mr-1 mb-1" title="Transcript database">
        {{ db }}
        <button class="btn btn-link btn-sm p-0 ml-1" title="Reset to RefSeq" @click="clearDb()">
          <i-mdi-close />
        </button>
      </span>
    </div>
  </div>
</template>

<style scoped>
.badge { display: inline-flex; align-items: center; }
</style>