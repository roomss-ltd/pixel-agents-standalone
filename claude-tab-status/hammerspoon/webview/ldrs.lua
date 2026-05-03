-- webview/ldrs.lua - local LDRS web-component bundle for the Hammerspoon renderer.
-- Generated from ldrs 1.1.9 via webview/ldrs-entry.js.
-- Build command: npx esbuild claude-tab-status/hammerspoon/webview/ldrs-entry.js --bundle --format=iife --platform=browser --target=es2017 --minify

local M = {}

local BUNDLE = [====[
"use strict";(()=>{var q=Object.defineProperty;var U=(i,r,e)=>r in i?q(i,r,{enumerable:!0,configurable:!0,writable:!0,value:e}):i[r]=e;var t=(i,r,e)=>U(i,typeof r!="symbol"?r+"":r,e);var a=class extends HTMLElement{constructor(){super();t(this,"_propsToUpgrade",{});t(this,"shadow");t(this,"template");t(this,"defaultProps");t(this,"isAttached",!1);this.shadow=this.attachShadow({mode:"open"}),this.template=document.createElement("template")}storePropsToUpgrade(e){e.forEach((s=>{this.hasOwnProperty(s)&&this[s]!==void 0&&(this._propsToUpgrade[s]=this[s],delete this[s])}))}upgradeStoredProps(){Object.entries(this._propsToUpgrade).forEach((([e,s])=>{this.setAttribute(e,s)}))}reflect(e){e.forEach((s=>{Object.defineProperty(this,s,{set(o){"string,number".includes(typeof o)?this.setAttribute(s,o.toString()):this.removeAttribute(s)},get(){return this.getAttribute(s)}})}))}applyDefaultProps(e){this.defaultProps=e,Object.entries(e).forEach((([s,o])=>{this[s]=this[s]||o.toString()}))}};function l(i,r){return r.replace(/([-A-y])/g,",$1").split(",").filter((e=>e!=="")).map((e=>{var n;let s=(n=e.match(/(\d+\.?\d*)/g))==null?void 0:n[0],o=parseFloat(s)*i;return e.replace(s,o.toString())})).join(" ")}var T=":host{align-items:center;display:inline-flex;flex-shrink:0;height:calc(var(--uib-size)*.625);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{height:calc(var(--uib-size)*.625);overflow:visible;transform-origin:center;width:var(--uib-size)}.car{stroke:var(--uib-color);stroke-dasharray:100;stroke-dashoffset:0;animation:travel var(--uib-speed) ease-in-out infinite,fade var(--uib-speed) ease-out infinite;transition:stroke .5s ease;will-change:stroke-dasharray,stroke-dashoffset}.car,.track{stroke-linecap:round;stroke-linejoin:round}.track{stroke:var(--uib-color);opacity:var(--uib-bg-opacity)}@keyframes travel{0%{stroke-dashoffset:100}75%{stroke-dashoffset:0}}@keyframes fade{0%{opacity:0}20%,55%{opacity:1}to{opacity:0}}",c=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed","stroke","bg-opacity"]);t(this,"size");t(this,"color");t(this,"speed");t(this,"stroke");t(this,"bg-opacity");t(this,"d");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes),this.d="M0.5,17.2h8.2l3-4.7l5.9,12l7.8-24l5.9,16.7v0h8.2"}static get observedAttributes(){return["size","color","speed","stroke","bg-opacity"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:50,color:"black",speed:1.5,stroke:4,"bg-opacity":.1});let e=parseInt(this.size),s=l(e/40,this.d);this.template.innerHTML=`
      <svg
        class="container" 
        x="0px" 
        y="0px"
        viewBox="0 0 ${this.size} ${.625*e}"
        height="${.625*e}"
        width="${this.size}"
        preserveAspectRatio='xMidYMid meet'
      >
        <path 
          class="track"
          stroke-width="${this.stroke}" 
          fill="none" 
          pathlength="100"
          d="${s}"
        />
        <path 
          class="car"
          stroke-width="${this.stroke}" 
          fill="none" 
          pathlength="100"
          d="${s}"
        />
      </svg>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
          --uib-bg-opacity: ${this["bg-opacity"]};
        }
        ${T}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=parseInt(this.size),s=this.shadow.querySelector("style"),o=this.shadow.querySelector("svg"),n=this.shadow.querySelectorAll("path");s&&(o.setAttribute("height",String(.625*e)),o.setAttribute("width",this.size),o.setAttribute("viewBox",`0 0 ${this.size} ${.625*e}`),n.forEach((S=>{S.setAttribute("stroke-width",this.stroke),S.setAttribute("d",l(e/40,this.d))})),s.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
        --uib-bg-opacity: ${this["bg-opacity"]};
      }
      ${T}
    `)}},g={register:(i="l-cardio")=>{customElements.get(i)||customElements.define(i,class extends c{})},element:c};var A=':host{--uib-dot-size:calc(var(--uib-size)*0.4);align-items:center;display:inline-flex;flex-shrink:0;height:var(--uib-size);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{align-items:center;animation:rotate calc(var(--uib-speed)*1.667) infinite linear;display:flex;height:var(--uib-size);justify-content:center;position:relative;width:var(--uib-size)}.container:after,.container:before{background-color:var(--uib-color);border-radius:50%;content:"";flex-shrink:0;height:var(--uib-dot-size);position:absolute;transition:background-color .3s ease;width:var(--uib-dot-size)}.container:before{animation:orbit var(--uib-speed) linear infinite}.container:after{animation:orbit var(--uib-speed) linear calc(var(--uib-speed)/-2) infinite}@keyframes rotate{0%{transform:rotate(0deg)}to{transform:rotate(1turn)}}@keyframes orbit{0%{opacity:.65;transform:translateX(calc(var(--uib-size)*.25)) scale(.73684)}5%{opacity:.58;transform:translateX(calc(var(--uib-size)*.235)) scale(.684208)}10%{opacity:.51;transform:translateX(calc(var(--uib-size)*.182)) scale(.631576)}15%{opacity:.44;transform:translateX(calc(var(--uib-size)*.129)) scale(.578944)}20%{opacity:.37;transform:translateX(calc(var(--uib-size)*.076)) scale(.526312)}25%{opacity:.3;transform:translateX(0) scale(.47368)}30%{opacity:.37;transform:translateX(calc(var(--uib-size)*-.076)) scale(.526312)}35%{opacity:.44;transform:translateX(calc(var(--uib-size)*-.129)) scale(.578944)}40%{opacity:.51;transform:translateX(calc(var(--uib-size)*-.182)) scale(.631576)}45%{opacity:.58;transform:translateX(calc(var(--uib-size)*-.235)) scale(.684208)}50%{opacity:.65;transform:translateX(calc(var(--uib-size)*-.25)) scale(.73684)}55%{opacity:.72;transform:translateX(calc(var(--uib-size)*-.235)) scale(.789472)}60%{opacity:.79;transform:translateX(calc(var(--uib-size)*-.182)) scale(.842104)}65%{opacity:.86;transform:translateX(calc(var(--uib-size)*-.129)) scale(.894736)}70%{opacity:.93;transform:translateX(calc(var(--uib-size)*-.076)) scale(.947368)}75%{opacity:1;transform:translateX(0) scale(1)}80%{opacity:.93;transform:translateX(calc(var(--uib-size)*.076)) scale(.947368)}85%{opacity:.86;transform:translateX(calc(var(--uib-size)*.129)) scale(.894736)}90%{opacity:.79;transform:translateX(calc(var(--uib-size)*.182)) scale(.842104)}95%{opacity:.72;transform:translateX(calc(var(--uib-size)*.235)) scale(.789472)}to{opacity:.65;transform:translateX(calc(var(--uib-size)*.25)) scale(.73684)}}',d=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed"]);t(this,"size");t(this,"color");t(this,"speed");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes)}static get observedAttributes(){return["size","color","speed"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:35,color:"black",speed:1.5}),this.template.innerHTML=`
      <div class="container"></div>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
        }
        ${A}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style");e&&(e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
      }
      ${A}
    `)}},y={register:(i="l-chaotic-orbit")=>{customElements.get(i)||customElements.define(i,class extends d{})},element:d};var _=':host{align-items:center;display:inline-flex;flex-shrink:0;height:var(--uib-size);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{height:var(--uib-size);position:relative;width:var(--uib-size)}.container,.dot{align-items:center;display:flex;justify-content:flex-start}.dot{height:100%;left:0;position:absolute;top:0;width:100%}.dot:before{animation:pulse calc(var(--uib-speed)*1.111) ease-in-out infinite;background-color:var(--uib-color);border-radius:50%;content:"";height:20%;opacity:.5;transform:scale(0);transition:background-color .3s ease;width:20%}.dot:nth-child(2){transform:rotate(45deg)}.dot:nth-child(2):before{animation-delay:calc(var(--uib-speed)*-.875)}.dot:nth-child(3){transform:rotate(90deg)}.dot:nth-child(3):before{animation-delay:calc(var(--uib-speed)*-.75)}.dot:nth-child(4){transform:rotate(135deg)}.dot:nth-child(4):before{animation-delay:calc(var(--uib-speed)*-.625)}.dot:nth-child(5){transform:rotate(180deg)}.dot:nth-child(5):before{animation-delay:calc(var(--uib-speed)*-.5)}.dot:nth-child(6){transform:rotate(225deg)}.dot:nth-child(6):before{animation-delay:calc(var(--uib-speed)*-.375)}.dot:nth-child(7){transform:rotate(270deg)}.dot:nth-child(7):before{animation-delay:calc(var(--uib-speed)*-.25)}.dot:nth-child(8){transform:rotate(315deg)}.dot:nth-child(8):before{animation-delay:calc(var(--uib-speed)*-.125)}@keyframes pulse{0%,to{opacity:.5;transform:scale(0)}50%{opacity:1;transform:scale(1)}}',h=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed"]);t(this,"size");t(this,"color");t(this,"speed");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes)}static get observedAttributes(){return["size","color","speed"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:40,color:"black",speed:.9}),this.template.innerHTML=`
      <div class="container">
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
      </div>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
        }
        ${_}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style");e&&(e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
      }
      ${_}
    `)}},z={register:(i="l-dot-spinner")=>{customElements.get(i)||customElements.define(i,class extends h{})},element:h};var E=':host{align-items:center;display:inline-flex;flex-shrink:0;height:calc(var(--uib-size)*.8);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{--uib-dot-size:calc(var(--uib-size)*0.1);height:calc(var(--uib-size)*.64);position:relative;width:calc(var(--uib-size)*.64)}.container,.dot{align-items:center;display:flex;justify-content:flex-start}.dot{--uib-d1:-0.48;--uib-d2:-0.4;--uib-d3:-0.32;--uib-d4:-0.24;--uib-d5:-0.16;--uib-d6:-0.08;--uib-d7:-0;animation:jump var(--uib-speed) ease-in-out infinite;backface-visibility:hidden;bottom:calc(var(--uib-bottom) + var(--uib-dot-size)/2);height:var(--uib-dot-size);opacity:var(--uib-scale);position:absolute;right:calc(var(--uib-right) + var(--uib-dot-size)/2);width:var(--uib-dot-size);will-change:transform}.dot:before{background-color:var(--uib-color);border-radius:50%;content:"";height:100%;transform:scale(var(--uib-scale));transition:background-color .3s ease;width:100%}.dot:first-child{--uib-bottom:24%;--uib-right:-35%;animation-delay:calc(var(--uib-speed)*var(--uib-d1))}.dot:nth-child(2){--uib-bottom:16%;--uib-right:-6%;animation-delay:calc(var(--uib-speed)*var(--uib-d2))}.dot:nth-child(3){--uib-bottom:8%;--uib-right:23%;animation-delay:calc(var(--uib-speed)*var(--uib-d3))}.dot:nth-child(4){--uib-bottom:-1%;--uib-right:51%;animation-delay:calc(var(--uib-speed)*var(--uib-d4))}.dot:nth-child(5){--uib-bottom:38%;--uib-right:-17.5%;animation-delay:calc(var(--uib-speed)*var(--uib-d2))}.dot:nth-child(6){--uib-bottom:30%;--uib-right:10%;animation-delay:calc(var(--uib-speed)*var(--uib-d3))}.dot:nth-child(7){--uib-bottom:22%;--uib-right:39%;animation-delay:calc(var(--uib-speed)*var(--uib-d4))}.dot:nth-child(8){--uib-bottom:14%;--uib-right:67%;animation-delay:calc(var(--uib-speed)*var(--uib-d5))}.dot:nth-child(9){--uib-bottom:53%;--uib-right:-0.8%;animation-delay:calc(var(--uib-speed)*var(--uib-d3))}.dot:nth-child(10){--uib-bottom:44.5%;--uib-right:27%;animation-delay:calc(var(--uib-speed)*var(--uib-d4))}.dot:nth-child(11){--uib-bottom:36%;--uib-right:55.7%;animation-delay:calc(var(--uib-speed)*var(--uib-d5))}.dot:nth-child(12){--uib-bottom:28.7%;--uib-right:84.3%;animation-delay:calc(var(--uib-speed)*var(--uib-d6))}.dot:nth-child(13){--uib-bottom:66.8%;--uib-right:15%;animation-delay:calc(var(--uib-speed)*var(--uib-d4))}.dot:nth-child(14){--uib-bottom:58.8%;--uib-right:43%;animation-delay:calc(var(--uib-speed)*var(--uib-d5))}.dot:nth-child(15){--uib-bottom:50%;--uib-right:72%;animation-delay:calc(var(--uib-speed)*var(--uib-d6))}.dot:nth-child(16){--uib-bottom:42%;--uib-right:100%;animation-delay:calc(var(--uib-speed)*var(--uib-d7))}.dot:nth-child(3){--uib-scale:0.98}.dot:nth-child(2),.dot:nth-child(8){--uib-scale:0.96}.dot:first-child,.dot:nth-child(7){--uib-scale:0.94}.dot:nth-child(12),.dot:nth-child(6){--uib-scale:0.92}.dot:nth-child(11),.dot:nth-child(5){--uib-scale:0.9}.dot:nth-child(10),.dot:nth-child(16){--uib-scale:0.88}.dot:nth-child(15),.dot:nth-child(9){--uib-scale:0.86}.dot:nth-child(14){--uib-scale:0.84}.dot:nth-child(13){--uib-scale:0.82}@keyframes jump{0%,to{transform:translateY(120%)}50%{transform:translateY(-120%)}}',u=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed"]);t(this,"size");t(this,"color");t(this,"speed");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes)}static get observedAttributes(){return["size","color","speed"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:60,color:"black",speed:1.5}),this.template.innerHTML=`
      <div class="container">
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
      </div>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
        }
        ${E}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style");e&&(e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
      }
      ${E}
    `)}},x={register:(i="l-grid")=>{customElements.get(i)||customElements.define(i,class extends u{})},element:u};var X=':host{align-items:center;display:inline-flex;flex-shrink:0;height:var(--uib-size);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{animation:rotate calc(var(--uib-speed)*2) ease-in-out infinite;display:flex;flex-direction:column;height:100%;position:relative;transform:rotate(45deg);width:100%}.half{--uib-half-size:calc(var(--uib-size)*0.435);align-items:center;display:flex;height:var(--uib-half-size);isolation:isolate;justify-content:center;overflow:hidden;position:absolute;width:var(--uib-half-size)}.half:first-child{left:8.25%;top:8.25%}.half:first-child,.half:last-child{border-radius:50% 50% calc(var(--uib-size)/15)}.half:last-child{align-self:flex-end;bottom:8.25%;right:8.25%;transform:rotate(180deg)}.half:last-child:after{animation-delay:calc(var(--uib-speed)*-1)}.half:before{left:0;opacity:var(--uib-bg-opacity);position:absolute;top:0}.half:after,.half:before{background-color:var(--uib-color);content:"";height:110%;transition:background-color .3s ease;width:110%}.half:after{animation:flow calc(var(--uib-speed)*2) linear infinite both;border-radius:0 0 calc(var(--uib-size)/20) 0;display:block;position:relative;transform:rotate(45deg) translate(-3%,50%) scaleX(1.2);transform-origin:bottom right;z-index:1}@keyframes flow{0%{transform:rotate(45deg) translate(-3%,50%) scaleX(1.2)}30%{transform:rotate(45deg) translate(115%,50%) scaleX(1.2)}30.001%,50%{transform:rotate(0deg) translate(-85%,-85%) scaleX(1)}80%,to{transform:rotate(0deg) translate(0) scaleX(1)}}@keyframes rotate{0%,30%{transform:rotate(45deg)}50%,80%{transform:rotate(225deg)}to{transform:rotate(405deg)}}',p=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed","bg-opacity"]);t(this,"size");t(this,"color");t(this,"speed");t(this,"bg-opacity");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes)}static get observedAttributes(){return["size","color","speed","bg-opacity"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:40,color:"black",speed:1.75,"bg-opacity":.1}),this.template.innerHTML=`
      <div class="container">
        <div class="half"></div>
        <div class="half"></div>
      </div>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
          --uib-bg-opacity: ${this["bg-opacity"]};
        }
        ${X}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style");e&&(e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
        --uib-bg-opacity: ${this["bg-opacity"]};
      }
      ${X}
    `)}},k={register:(i="l-hourglass")=>{customElements.get(i)||customElements.define(i,class extends p{})},element:p};var M=':host{align-items:center;display:inline-flex;flex-shrink:0;height:calc(var(--uib-size)*.63);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{height:var(--uib-size);position:relative;top:8%;width:var(--uib-size)}.container,.dot{align-items:center;display:flex;justify-content:flex-start}.dot{animation:swing var(--uib-speed) linear infinite;height:100%;left:0;position:absolute;top:13.5%;width:100%}.dot:before{background-color:var(--uib-color);border-radius:50%;content:"";height:25%;transition:background-color .3s ease;width:25%}.dot:first-child{animation-delay:calc(var(--uib-speed)*-.36)}.dot:nth-child(2){animation-delay:calc(var(--uib-speed)*-.27);opacity:.8}.dot:nth-child(2):before{transform:scale(.9)}.dot:nth-child(3){animation-delay:calc(var(--uib-speed)*-.18);opacity:.6}.dot:nth-child(3):before{transform:scale(.8)}.dot:nth-child(4){animation-delay:calc(var(--uib-speed)*-.09);opacity:.4}.dot:nth-child(4):before{transform:scale(.7)}@keyframes swing{0%{transform:rotate(0deg)}15%{transform:rotate(0deg)}50%{transform:rotate(180deg)}65%{transform:rotate(180deg)}to{transform:rotate(0deg)}}',b=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed"]);t(this,"size");t(this,"color");t(this,"speed");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes)}static get observedAttributes(){return["size","color","speed"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:40,color:"black",speed:1.6}),this.template.innerHTML=`
      <div class="container">
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
      </div>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
        }
        ${M}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style");e&&(e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
      }
      ${M}
    `)}},$={register:(i="l-metronome")=>{customElements.get(i)||customElements.define(i,class extends b{})},element:b};var j=':host{align-items:center;display:inline-flex;flex-shrink:0;height:var(--uib-size);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{animation:rotate calc(var(--uib-speed)*4) linear infinite;height:var(--uib-size);position:relative;width:var(--uib-size)}@keyframes rotate{0%{transform:rotate(0deg)}to{transform:rotate(1turn)}}.particle{align-items:center;display:flex;height:100%;justify-content:center;left:0;position:absolute;top:0;width:100%}.particle:first-child{--uib-delay:0;transform:rotate(8deg)}.particle:nth-child(2){--uib-delay:-0.4;transform:rotate(36deg)}.particle:nth-child(3){--uib-delay:-0.9;transform:rotate(72deg)}.particle:nth-child(4){--uib-delay:-0.5;transform:rotate(90deg)}.particle:nth-child(5){--uib-delay:-0.3;transform:rotate(144deg)}.particle:nth-child(6){--uib-delay:-0.2;transform:rotate(180deg)}.particle:nth-child(7){--uib-delay:-0.6;transform:rotate(216deg)}.particle:nth-child(8){--uib-delay:-0.7;transform:rotate(252deg)}.particle:nth-child(9){--uib-delay:-0.1;transform:rotate(300deg)}.particle:nth-child(10){--uib-delay:-0.8;transform:rotate(324deg)}.particle:nth-child(11){--uib-delay:-1.2;transform:rotate(335deg)}.particle:nth-child(12){--uib-delay:-0.5;transform:rotate(290deg)}.particle:nth-child(13){--uib-delay:-0.2;transform:rotate(240deg)}.particle:before{--uib-d:calc(var(--uib-delay)*var(--uib-speed));animation:orbit var(--uib-speed) linear var(--uib-d) infinite;background-color:var(--uib-color);border-radius:50%;content:"";flex-shrink:0;height:17.5%;position:absolute;transition:background-color .3s ease;width:17.5%}@keyframes orbit{0%{opacity:.65;transform:translate(calc(var(--uib-size)*.5)) scale(.73684)}5%{opacity:.58;transform:translate(calc(var(--uib-size)*.4)) scale(.684208)}10%{opacity:.51;transform:translate(calc(var(--uib-size)*.3)) scale(.631576)}15%{opacity:.44;transform:translate(calc(var(--uib-size)*.2)) scale(.578944)}20%{opacity:.37;transform:translate(calc(var(--uib-size)*.1)) scale(.526312)}25%{opacity:.3;transform:translate(0) scale(.47368)}30%{opacity:.37;transform:translate(calc(var(--uib-size)*-.1)) scale(.526312)}35%{opacity:.44;transform:translate(calc(var(--uib-size)*-.2)) scale(.578944)}40%{opacity:.51;transform:translate(calc(var(--uib-size)*-.3)) scale(.631576)}45%{opacity:.58;transform:translate(calc(var(--uib-size)*-.4)) scale(.684208)}50%{opacity:.65;transform:translate(calc(var(--uib-size)*-.5)) scale(.73684)}55%{opacity:.72;transform:translate(calc(var(--uib-size)*-.4)) scale(.789472)}60%{opacity:.79;transform:translate(calc(var(--uib-size)*-.3)) scale(.842104)}65%{opacity:.86;transform:translate(calc(var(--uib-size)*-.2)) scale(.894736)}70%{opacity:.93;transform:translate(calc(var(--uib-size)*-.1)) scale(.947368)}75%{opacity:1;transform:translate(0) scale(1)}80%{opacity:.93;transform:translate(calc(var(--uib-size)*.1)) scale(.947368)}85%{opacity:.86;transform:translate(calc(var(--uib-size)*.2)) scale(.894736)}90%{opacity:.79;transform:translate(calc(var(--uib-size)*.3)) scale(.842104)}95%{opacity:.72;transform:translate(calc(var(--uib-size)*.4)) scale(.789472)}to{opacity:.65;transform:translate(calc(var(--uib-size)*.5)) scale(.73684)}}',f=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed"]);t(this,"size");t(this,"color");t(this,"speed");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes)}static get observedAttributes(){return["size","color","speed"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:45,color:"black",speed:1.75}),this.template.innerHTML=`
      <div class="container">
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
        <div class="particle"></div>
      </div>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
        }
        ${j}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style");e&&(e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
      }
      ${j}
    `)}},w={register:(i="l-quantum")=>{customElements.get(i)||customElements.define(i,class extends f{})},element:f};var H=":host{align-items:center;display:inline-flex;flex-shrink:0;height:var(--uib-size);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{height:var(--uib-size);overflow:visible;transform-origin:center;width:var(--uib-size)}.car{fill:none;stroke:var(--uib-color);stroke-dasharray:var(--uib-dash),var(--uib-gap);stroke-dashoffset:0;stroke-linecap:round;animation:travel var(--uib-speed) linear infinite;will-change:stroke-dasharray,stroke-dashoffset}.car,.track{transition:stroke .5s ease}.track{stroke:var(--uib-color);opacity:var(--uib-bg-opacity)}@keyframes travel{0%{stroke-dashoffset:0}to{stroke-dashoffset:100}}",m=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed","stroke","stroke-length","bg-opacity"]);t(this,"size");t(this,"color");t(this,"speed");t(this,"stroke");t(this,"stroke-length");t(this,"bg-opacity");t(this,"d");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes),this.d="M49.5,42.9c0-18.1-9.9-34-24.5-42.4C10.4,9,0.5,24.8,0.5,42.9c7.2,4.2,15.6,6.6,24.5,6.6S42.3,47.1,49.5,42.9z"}static get observedAttributes(){return["size","color","speed","stroke","stroke-length","bg-opacity"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:37,color:"black",stroke:5,speed:.9,"stroke-length":.15,"bg-opacity":.1});let e=l(parseInt(this.size)/50,this.d);this.template.innerHTML=`
      <svg
        class="container" 
        x="0px" 
        y="0px"
        viewBox="0 0 ${this.size} ${this.size}"
        height="${this.size}"
        width="${this.size}"
        preserveAspectRatio='xMidYMid meet'
      >
        <path
          class="track" 
          fill="none" 
          stroke-width="${this.stroke}" 
          pathlength="100"
          d="${e}"
        />

        <path
          class="car" 
          fill="none" 
          stroke-width="${this.stroke}" 
          pathlength="100"
          d="${e}"
        />
      </svg>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
          --uib-dash: ${100*parseFloat(this["stroke-length"])};
          --uib-gap: ${100-100*parseFloat(this["stroke-length"])};
          --uib-bg-opacity: ${this["bg-opacity"]};
        }
        ${H}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style"),s=this.shadow.querySelector("svg"),o=this.shadow.querySelectorAll("path");e&&(s.setAttribute("height",this.size),s.setAttribute("width",this.size),s.setAttribute("viewBox",`0 0 ${this.size} ${this.size}`),o.forEach((n=>{n.setAttribute("stroke-width",this.stroke),n.setAttribute("d",l(parseInt(this.size)/50,this.d))})),e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
        --uib-dash: ${100*parseFloat(this["stroke-length"])};
        --uib-gap: ${100-100*parseFloat(this["stroke-length"])};
        --uib-bg-opacity: ${this["bg-opacity"]};
      }
      ${H}
    `)}},C={register:(i="l-reuleaux")=>{customElements.get(i)||customElements.define(i,class extends m{})},element:m};var L=':host{align-items:center;display:inline-flex;flex-shrink:0;height:var(--uib-size);justify-content:center;width:var(--uib-size)}:host([hidden]){display:none}.container{--uib-dot-size:25%;animation:spin var(--uib-speed) infinite linear;display:inline-block;height:var(--uib-size);position:relative;width:var(--uib-size)}.dot{height:100%;left:calc(50% - var(--uib-dot-size)/2);width:var(--uib-dot-size)}.dot,.dot:after{position:absolute}.dot:after{background-color:var(--uib-color);border-radius:50%;content:"";height:0;left:0;padding-bottom:100%;top:0;transition:background-color .3s ease;width:100%}.dot:first-child{transform:rotate(120deg)}.dot:first-child:after{animation:wobble var(--uib-speed) infinite ease-in-out}.dot:nth-child(2){transform:rotate(-120deg)}.dot:nth-child(2):after,.dot:nth-child(3):after{animation:wobble var(--uib-speed) infinite ease-in-out}@keyframes spin{0%{transform:rotate(0deg)}to{transform:rotate(1turn)}}@keyframes wobble{0%,to{transform:translateY(0)}50%{transform:translateY(65%)}}',v=class extends a{constructor(){super();t(this,"_attributes",["size","color","speed"]);t(this,"size");t(this,"color");t(this,"speed");this.storePropsToUpgrade(this._attributes),this.reflect(this._attributes)}static get observedAttributes(){return["size","color","speed"]}connectedCallback(){this.upgradeStoredProps(),this.applyDefaultProps({size:40,color:"black",speed:1.3}),this.template.innerHTML=`
      <div class="container">
        <div class="dot"></div>
        <div class="dot"></div>
        <div class="dot"></div>
      </div>
      <style>
        :host{
          --uib-size: ${this.size}px;
          --uib-color: ${this.color};
          --uib-speed: ${this.speed}s;
        }
        ${L}
      </style>
    `,this.shadow.replaceChildren(this.template.content.cloneNode(!0))}attributeChangedCallback(){let e=this.shadow.querySelector("style");e&&(e.innerHTML=`
      :host{
        --uib-size: ${this.size}px;
        --uib-color: ${this.color};
        --uib-speed: ${this.speed}s;
      }
      ${L}
    `)}},P={register:(i="l-trio")=>{customElements.get(i)||customElements.define(i,class extends v{})},element:v};z.register();w.register();g.register();P.register();x.register();y.register();k.register();$.register();C.register();})();
]====]

function M.script()
    return BUNDLE
end

return M
