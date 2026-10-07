extension PlanPage {
    /// What the page does with the plan: paints the header and the cards where `PlanDrawing`
    /// put them, then lets you move round it. Scroll or drag moves, pinch or ⌘-scroll zooms,
    /// and clicking a card lights what it waits on and what waits on it, dimming the rest.
    ///
    /// ponytail: a reload — which the Page tab does whenever the agent rewrites the plan —
    /// fits the plan again and forgets the pick. Keep both across reloads if a plan that
    /// changes while someone is reading it turns out to be common.
    static let script = #"""
        const plan = JSON.parse(document.getElementById('plan').textContent);
        const $ = (id) => document.getElementById(id);
        function el(tag, className, text) {
          const node = document.createElement(tag);
          if (className) node.className = className;
          if (text != null) node.textContent = text;
          return node;
        }

        // The header: what the plan gives, and what it needs from you.
        document.title = plan.title;
        $('title').textContent = plan.title;
        const tasks = plan.nodes.filter((n) => n.kind === 'task');
        const ready = tasks.filter((n) => n.ready).length;
        const asks = plan.needsYou.length;
        const chips = [[tasks.length + (tasks.length === 1 ? ' task' : ' tasks'), '']];
        if (ready) chips.push([ready + ' ready to start', 'green']);
        if (asks) chips.push([asks + (asks === 1 ? ' needs you' : ' need you'), 'amber']);
        for (const n of plan.nodes) if (n.kind === 'pending') chips.push(['Waits on ' + n.title, 'pending']);
        for (const [text, tone] of chips) $('chips').append(el('span', 'chip ' + tone, text));
        // Four lines at most, one line each: the page is read in seconds, the draft holds the rest.
        for (const text of plan.outcomes.slice(0, 4)) {
          const li = el('li');
          li.title = text;
          li.append(el('span', 'text', text));
          $('outcomes').append(li);
        }
        for (const ask of plan.needsYou) {
          const li = el('li');
          li.title = ask.action;
          li.append(el('span', 'text', ask.action), el('span', 'id', ask.task));
          $('asks').append(li);
        }
        $('gets').hidden = !plan.outcomes.length;
        $('needs').hidden = !asks;
        $('lists').hidden = !plan.outcomes.length && !asks;

        // The graph, where the app laid it out.
        const world = $('world');
        const svg = $('edges');
        const px = (node, x, y, width, height) => {
          node.style.left = x + 'px';
          node.style.top = y + 'px';
          if (width != null) node.style.width = width + 'px';
          if (height != null) node.style.height = height + 'px';
        };
        px(world, 0, 0, plan.width, plan.height);
        svg.setAttribute('width', plan.width);
        svg.setAttribute('height', plan.height);
        for (const band of plan.bands) {
          const box = el('div', 'band');
          px(box, band.x, band.y, band.width, band.height);
          if (band.title) box.append(el('span', null, band.title));
          world.insertBefore(box, svg);
        }
        const up = {};
        const down = {};
        const paths = plan.edges.map((edge) => {
          (up[edge.to] ??= []).push(edge.from);
          (down[edge.from] ??= []).push(edge.to);
          const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
          const bend = Math.max(24, (edge.x2 - edge.x1) / 2);
          path.setAttribute('d', `M${edge.x1} ${edge.y1} C${edge.x1 + bend} ${edge.y1} ${edge.x2 - bend} ${edge.y2} ${edge.x2 - 4} ${edge.y2}`);
          path.setAttribute('class', edge.dashed ? 'edge dashed' : 'edge');
          path.setAttribute('marker-end', 'url(#head)');
          svg.append(path);
          return { edge, path };
        });
        const cards = new Map();
        for (const n of plan.nodes) {
          const card = el('button', 'node ' + n.kind + (n.ready ? ' ready' : ''));
          card.type = 'button';
          card.title = n.title;
          px(card, n.x, n.y, plan.nodeWidth, plan.nodeHeight);
          const title = el('span', 'title', n.title);
          if (n.ready) title.prepend(el('span', 'dot'));
          const meta = el('span', 'meta');
          meta.append(el('span', 'id', n.id));
          if (n.design) meta.append(el('span', 'pill design', 'Design'));
          if (n.you) meta.append(el('span', 'pill you', 'You'));
          card.append(title, meta);
          card.addEventListener('click', () => { if (!moved) pick(n); });
          world.append(card);
          const parts = [card];
          if (n.caption) {
            const caption = el('span', 'caption', n.caption);
            px(caption, n.x, n.y + plan.nodeHeight + 6);
            caption.style.maxWidth = plan.nodeWidth + 'px';
            world.append(caption);
            parts.push(caption);
          }
          cards.set(n.id, parts);
        }

        // Tracing: a picked card, everything upstream and downstream of it, and nothing else.
        function reach(id, graph, seen = new Set()) {
          for (const next of graph[id] ?? []) if (!seen.has(next)) { seen.add(next); reach(next, graph, seen); }
          return seen;
        }
        function pick(n) {
          const before = reach(n.id, up).add(n.id);
          const after = reach(n.id, down).add(n.id);
          for (const [id, parts] of cards) {
            const lit = before.has(id) || after.has(id);
            for (const part of parts) part.classList.toggle('dim', !lit);
            parts[0].classList.toggle('lit', lit && id !== n.id);
            parts[0].classList.toggle('focus', id === n.id);
          }
          for (const { edge, path } of paths) {
            const lit = (before.has(edge.from) && before.has(edge.to)) || (after.has(edge.from) && after.has(edge.to));
            path.classList.toggle('lit', lit);
            path.classList.toggle('dim', !lit);
            path.setAttribute('marker-end', lit ? 'url(#head-lit)' : 'url(#head)');
          }
          show(n);
        }
        function show(n) {
          const where = n.kind === 'task' ? '' : (n.kind === 'built' ? 'Built already' : 'Not built yet') + (n.caption ? ' · ' + n.caption : '');
          const list = el('dl');
          for (const [label, ids] of [['Waits on', up[n.id]], ['Unblocks', down[n.id]]]) {
            if (ids?.length) list.append(el('dt', null, label), el('dd', null, ids.join(', ')));
          }
          $('detail').replaceChildren(
            el('span', 'id', n.id), el('h3', null, n.title),
            ...[n.detail, where].filter(Boolean).map((text) => el('p', null, text)),
            ...(list.childElementCount ? [list] : []),
            el('p', 'foot', 'To change it, tell Product in the session.'));
          $('detail').hidden = false;
          $('hint').hidden = true;
        }
        function clear() {
          for (const parts of cards.values()) for (const part of parts) part.classList.remove('dim', 'lit', 'focus');
          for (const { path } of paths) {
            path.classList.remove('lit', 'dim');
            path.setAttribute('marker-end', 'url(#head)');
          }
          $('detail').hidden = true;
          $('hint').hidden = false;
        }

        // Moving round: everything in the world moves as one, by one transform.
        const view = $('view');
        let scale = 1, x = 0, y = 0, touched = false, drag = null, moved = false, pinch = 1;
        function apply() {
          world.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
          $('pct').textContent = Math.round(scale * 100) + '%';
        }
        function zoom(to, cx, cy) {
          const next = Math.min(2, Math.max(0.25, to));
          x = cx - (cx - x) * next / scale;
          y = cy - (cy - y) * next / scale;
          scale = next;
          touched = true;
          apply();
        }
        // Never above 100%, and clear of the legend along the bottom.
        function fit() {
          const room = view.getBoundingClientRect();
          const legend = 60;
          scale = Math.max(0.25, Math.min(1, room.width / plan.width, (room.height - legend) / plan.height));
          x = Math.max(0, (room.width - plan.width * scale) / 2);
          y = Math.max(0, (room.height - legend - plan.height * scale) / 2);
          touched = false;
          apply();
        }
        const at = (e) => { const room = view.getBoundingClientRect(); return [e.clientX - room.left, e.clientY - room.top]; };
        const middle = () => { const room = view.getBoundingClientRect(); return [room.width / 2, room.height / 2]; };
        $('in').addEventListener('click', () => zoom(scale * 1.25, ...middle()));
        $('out').addEventListener('click', () => zoom(scale / 1.25, ...middle()));
        $('fit').addEventListener('click', fit);
        view.addEventListener('wheel', (e) => {
          e.preventDefault();
          if (e.ctrlKey || e.metaKey) return zoom(scale * Math.exp(-e.deltaY / 200), ...at(e));
          x -= e.deltaX;
          y -= e.deltaY;
          touched = true;
          apply();
        }, { passive: false });
        view.addEventListener('gesturestart', (e) => { e.preventDefault(); pinch = scale; });
        view.addEventListener('gesturechange', (e) => { e.preventDefault(); zoom(pinch * e.scale, ...at(e)); });
        view.addEventListener('pointerdown', (e) => {
          if (e.button !== 0 || e.target.closest('.overlay')) return;
          drag = { x: e.clientX, y: e.clientY, startX: x, startY: y };
          moved = false;
        });
        addEventListener('pointermove', (e) => {
          if (!drag || (!moved && Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 4)) return;
          moved = true;
          view.classList.add('dragging');
          x = drag.startX + e.clientX - drag.x;
          y = drag.startY + e.clientY - drag.y;
          touched = true;
          apply();
        });
        addEventListener('pointerup', () => { drag = null; view.classList.remove('dragging'); });
        view.addEventListener('click', (e) => { if (!moved && !e.target.closest('.node, .overlay')) clear(); });
        addEventListener('keydown', (e) => { if (e.key === 'Escape') clear(); });
        addEventListener('resize', () => { if (!touched) fit(); });
        fit();
        """#
}
