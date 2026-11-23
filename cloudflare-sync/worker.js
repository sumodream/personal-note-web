// Cloudflare Worker：灵感工作台云同步（R2 存单一 JSON）
// 路由：/api/sync  GET=拉取  PUT=推送  OPTIONS=预检
// 环境变量：SYNC_TOKEN（secret，必需）、OBJECT_KEY（可选，默认 state.json）
// R2 绑定：BUCKET

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,PUT,OPTIONS',
  'Access-Control-Allow-Headers': 'authorization,content-type',
  'Access-Control-Max-Age': '86400',
  'Cache-Control': 'no-store'
};

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status: status || 200,
    headers: Object.assign({ 'Content-Type': 'application/json; charset=utf-8' }, CORS)
  });
}

// 常量时间比较，避免逐字符提前返回造成的时序泄漏
function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function newVersion() {
  return Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 7);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);
    if (url.pathname.replace(/\/+$/, '') !== '/api/sync') {
      return json({ error: 'not found' }, 404);
    }

    // 口令校验
    const auth = request.headers.get('Authorization') || '';
    const token = auth.replace(/^Bearer\s+/i, '').trim();
    if (!env.SYNC_TOKEN) return json({ error: 'server missing SYNC_TOKEN' }, 500);
    if (!safeEqual(token, env.SYNC_TOKEN)) return json({ error: 'unauthorized' }, 401);

    if (!env.BUCKET) return json({ error: 'R2 binding BUCKET missing' }, 500);
    const key = env.OBJECT_KEY || 'state.json';

    if (request.method === 'GET') {
      const obj = await env.BUCKET.get(key);
      if (!obj) return json({ empty: true }, 404);
      let cur = null;
      try { cur = JSON.parse(await obj.text()); } catch (e) { cur = null; }
      if (!cur || !cur.data) return json({ empty: true }, 404);
      return json({ version: cur.version || '', savedAt: cur.savedAt || 0, data: cur.data }, 200);
    }

    if (request.method === 'PUT') {
      let body = null;
      try { body = await request.json(); } catch (e) { body = null; }
      if (!body || typeof body.data !== 'object' || body.data === null) {
        return json({ error: 'data required' }, 400);
      }

      const cur = await env.BUCKET.get(key);
      let curEnv = null;
      if (cur) { try { curEnv = JSON.parse(await cur.text()); } catch (e) { curEnv = null; } }

      const force = body.force === true;
      const base = String(body.baseVersion || '');
      if (curEnv && curEnv.data && !force && base !== String(curEnv.version || '')) {
        return json({
          conflict: true,
          version: curEnv.version || '',
          savedAt: curEnv.savedAt || 0,
          data: curEnv.data
        }, 409);
      }

      const version = newVersion();
      const savedAt = Date.now();
      const payload = JSON.stringify({ version: version, savedAt: savedAt, data: body.data });
      await env.BUCKET.put(key, payload, {
        httpMetadata: { contentType: 'application/json; charset=utf-8' }
      });
      return json({ ok: true, version: version, savedAt: savedAt }, 200);
    }

    return json({ error: 'method not allowed' }, 405);
  }
};
