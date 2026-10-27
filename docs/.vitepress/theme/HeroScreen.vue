<script setup lang="ts">
import { withBase } from "vitepress";
</script>

<template>
  <div class="sf-cabinet">
    <div class="sf-marquee">
      <span class="sf-blink">PRESS START</span>
      <span>FREE PLAY</span>
    </div>
    <div class="sf-crt">
      <img :src="withBase('/media/title.png')" alt="Street fAIghter title screen" />
    </div>
  </div>
</template>
