// Framework-level automatic same-layer proximity fusion for `Glass::liquid(layer>0)` surfaces:
// collects painted liquid glass subtrees (`GlassSlot`) in `Ctx::view_paint`, clusters disjoint
// same-layer slots whose 2D signed edge gap is `< break_gap` (up to 8 shapes per cluster matching
// GPU `shape[8]`), and reorders instances in-place at the cluster's anchor so shadows sit strictly
// beneath the merged `kind == 6` glass run, the merged glass instances are strictly adjacent with
// one shared negative capture id and gap-attenuated `slot 23` merge radius, and every member's
// subtree content (icons, labels, badges, menu rows) renders razor-sharp on top of the glass.
// Zero copies and zero allocations at rest when no cluster has >= 2 members.

///|
priv struct GlassSlot {
  layer : Int
  nav_scope : Int
  id : @view.NodeId
  glass_idx : Int
  shadow_idx : Int
  sub_start : Int
  mut sub_end : Int
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
  cx0 : Double
  cy0 : Double
  cx1 : Double
  cy1 : Double
  merge_max : Double
  break_gap : Double
}

///|
fn glass_slots_nav_compatible(a : Int, b : Int) -> Bool {
  a == b || a == 0 || b == 0
}

///|
fn glass_slots_clips_overlap(a : GlassSlot, b : GlassSlot) -> Bool {
  dmin(a.cx1, b.cx1) > dmax(a.cx0, b.cx0) && dmin(a.cy1, b.cy1) > dmax(a.cy0, b.cy0)
}

///|
fn glass_slot_gap(a : GlassSlot, b : GlassSlot) -> Double {
  let dx = dmax(0.0, dmax(a.x0 - b.x1, b.x0 - a.x1))
  let dy = dmax(0.0, dmax(a.y0 - b.y1, b.y0 - a.y1))
  if dx > 0.0 || dy > 0.0 {
    (dx * dx + dy * dy).sqrt()
  } else {
    -dmin(dmin(a.x1, b.x1) - dmax(a.x0, b.x0), dmin(a.y1, b.y1) - dmax(a.y0, b.y0))
  }
}

///|
fn glass_slot_break_gap(a : GlassSlot, b : GlassSlot) -> Double {
  if a.break_gap > 0.0 && b.break_gap > 0.0 {
    dmin(a.break_gap, b.break_gap)
  } else {
    dmax(a.break_gap, b.break_gap)
  }
}

///|
fn Ctx::merge_liquid_layers(self : Ctx, n0 : Int, slots : Array[GlassSlot]) -> Unit {
  let count = slots.length()
  if count < 2 || self.ninst <= n0 {
    return
  }
  // 1. Filter out slots whose subtree is strictly contained inside another slot of the same layer.
  let active : Array[GlassSlot] = []
  for i in 0..<count {
    let si = slots[i]
    if si.sub_start < n0 || si.sub_end > self.ninst || si.glass_idx < si.sub_start || si.glass_idx >= si.sub_end {
      continue
    }
    let mut nested = false
    for j in 0..<count {
      if i == j {
        continue
      }
      let sj = slots[j]
      if sj.layer == si.layer && sj.sub_start <= si.sub_start && si.sub_end <= sj.sub_end {
        if sj.sub_start < si.sub_start || si.sub_end < sj.sub_end || j < i {
          nested = true
          break
        }
      }
    }
    if !nested {
      active.push(si)
    }
  }
  let m = active.length()
  if m < 2 {
    return
  }
  // 2. Spatial BFS clustering per layer (max 8 shapes per cluster matching GPU `shape[8]`).
  let visited = Array::make(m, false)
  let clusters : Array[(Array[GlassSlot], Double, Int)] = []
  for i in 0..<m {
    if visited[i] {
      continue
    }
    visited[i] = true
    let layer = active[i].layer
    let mut cluster_scope = active[i].nav_scope
    let queue : Array[Int] = [i]
    let members : Array[Int] = [i]
    let mut head = 0
    let mut min_gap = 1.0e9
    let mut best_bg = 0.0
    let mut best_max_m = 0.0
    while head < queue.length() {
      let cur = queue[head]
      head += 1
      let sa = active[cur]
      for j in 0..<m {
        if active[j].layer != layer || j == cur {
          continue
        }
        let sb = active[j]
        if !glass_slots_nav_compatible(cluster_scope, sb.nav_scope) ||
          !glass_slots_nav_compatible(sa.nav_scope, sb.nav_scope) ||
          !glass_slots_clips_overlap(sa, sb) {
          continue
        }
        let bg = glass_slot_break_gap(sa, sb)
        let max_m = dmax(sa.merge_max, sb.merge_max)
        if max_m <= 0.0 || bg <= 0.0 {
          continue
        }
        let gap = glass_slot_gap(sa, sb)
        if gap < bg {
          if gap < min_gap {
            min_gap = gap
            best_bg = bg
            best_max_m = max_m
          }
          if !visited[j] && members.length() < 8 {
            visited[j] = true
            if cluster_scope == 0 && sb.nav_scope != 0 {
              cluster_scope = sb.nav_scope
            }
            members.push(j)
            queue.push(j)
          }
        }
      }
    }
    if members.length() >= 2 && best_bg > 0.0 && best_max_m > 0.0 {
      let cap_m = dmin(best_max_m, 2.0 * best_bg)
      let m_eff = if min_gap <= 0.0 {
        cap_m
      } else {
        let u = dclamp(min_gap / best_bg, 0.0, 1.0)
        let sm = u * u * (3.0 - 2.0 * u)
        cap_m * (1.0 - sm)
      }
      if m_eff > 0.01 {
        let list : Array[GlassSlot] = members.map(fn(idx) { active[idx] })
        list.sort_by(fn(a, b) { a.sub_start.compare(b.sub_start) })
        let mut anchor_pos = list[0].sub_end
        for s in list {
          if s.sub_end > anchor_pos {
            anchor_pos = s.sub_end
          }
        }
        clusters.push((list, m_eff, anchor_pos))
      }
    }
  }
  // Fast path: nothing to merge at rest -> zero copies, zero allocations.
  if clusters.is_empty() {
    return
  }
  // 3. Build exact permutation of [n0 ..< self.ninst] moving each cluster to its `anchor_pos` in
  //    [shadows] -> [strictly adjacent merged glass] -> [member subtree children] order.
  let total = self.ninst - n0
  let member_of = Array::make(total, -1)
  for ci in 0..<clusters.length() {
    let (list, _, _) = clusters[ci]
    for s in list {
      for k in s.sub_start..<s.sub_end {
        member_of[k - n0] = ci
      }
    }
  }
  let perm : Array[Int] = Array(capacity=total)
  let merged_runs : Array[(Int, Int, Double)] = []
  let emit_cluster = fn(ci : Int) -> Unit {
    let (list, m_eff, _) = clusters[ci]
    // (a) All shadows first, strictly beneath the merged liquid glass.
    for s in list {
      if s.shadow_idx >= 0 {
        perm.push(s.shadow_idx)
      }
    }
    // (b) All liquid glass instances strictly adjacent, highest opacity first so a fading-in trigger pill
    //     never overrides the full-opacity droplet's optical parameters in merged_liquid.
    let run_from = n0 + perm.length()
    let ordered = list.copy()
    ordered.sort_by(fn(a, b) {
      let oa = self.inst[a.glass_idx * inst_size + 15]
      let ob = self.inst[b.glass_idx * inst_size + 15]
      if oa > ob {
        -1
      } else if oa < ob {
        1
      } else {
        0
      }
    })
    for s in ordered {
      perm.push(s.glass_idx)
    }
    let run_to = n0 + perm.length()
    merged_runs.push((run_from, run_to, m_eff))
    // (c) All remaining subtree instances (icons, text, badges, menu rows) razor-sharp on top.
    for s in list {
      for k in s.sub_start..<s.sub_end {
        if k != s.glass_idx && k != s.shadow_idx {
          perm.push(k)
        }
      }
    }
  }
  for k in n0..<=self.ninst {
    for ci in 0..<clusters.length() {
      if clusters[ci].2 == k {
        emit_cluster(ci)
      }
    }
    if k < self.ninst && member_of[k - n0] == -1 {
      perm.push(k)
    }
  }
  if perm.length() != total {
    return
  }
  // 4. Apply permutation to `self.inst` and keep `ride_spans` / `list_heads` indices in sync.
  let saved = inst_copy(self.inst, n0 * inst_size, total * inst_size)
  let inv_perm = Array::make(total, 0)
  for dst_rel in 0..<total {
    let src_rel = perm[dst_rel] - n0
    inv_perm[src_rel] = n0 + dst_rel
    saved.blit_to(
      self.inst,
      len=inst_size,
      src_offset=src_rel * inst_size,
      dst_offset=(n0 + dst_rel) * inst_size,
    )
  }
  for j in 0..<ride_spans.length() {
    let idx = ride_spans[j]
    if idx >= n0 && idx < self.ninst {
      ride_spans[j] = inv_perm[idx - n0]
    }
  }
  for j in 0..<list_heads.length() {
    let idx = list_heads[j].at
    if idx >= n0 && idx < self.ninst {
      list_heads[j].at = inv_perm[idx - n0]
    }
  }
  // 5. Assign one fresh negative capture id & effective merge radius to each merged glass run.
  for run in merged_runs {
    let (from, to, m_eff) = run
    glass_paint.run = glass_paint.run + 1
    let cap = -glass_paint.run.to_double()
    for k in from..<to {
      let off = k * inst_size
      self.inst[off + 20] = cap
      self.inst[off + 23] = m_eff
    }
  }
  // 6. Keep `inst_owners` and `bone_insts` bit-identical with the permuted instance stream.
  if inst_owners_kept() {
    let o = inst_owners.owner
    let cl = inst_owners.cell
    let tr = inst_owners.tree
    let mk = inst_owners.mark
    let saved_o : Array[Int] = Array::make(total, -1)
    let saved_cl : Array[(Double, Double)] = Array::make(total, (0.0, 1.0))
    let saved_tr : Array[@view.NodeId?] = Array::make(total, None)
    let saved_mk : Array[Int] = Array::make(total, 0)
    for rel in 0..<total {
      let k = n0 + rel
      if k < o.length() {
        saved_o[rel] = o[k]
      }
      if k < cl.length() {
        saved_cl[rel] = cl[k]
      }
      if k < tr.length() {
        saved_tr[rel] = tr[k]
      }
      if k < mk.length() {
        saved_mk[rel] = mk[k]
      }
    }
    let has_bones = !bone_insts.is_empty()
    let saved_bones : Array[Bool] = if has_bones {
      Array::makei(total, fn(rel) { bone_insts.contains(n0 + rel) })
    } else {
      []
    }
    if has_bones {
      for rel in 0..<total {
        bone_insts.remove(n0 + rel)
      }
    }
    for dst_rel in 0..<total {
      let src_rel = perm[dst_rel] - n0
      let dst = n0 + dst_rel
      if dst < o.length() {
        o[dst] = saved_o[src_rel]
      }
      if dst < cl.length() {
        cl[dst] = saved_cl[src_rel]
      }
      if dst < tr.length() {
        tr[dst] = saved_tr[src_rel]
      }
      if dst < mk.length() {
        mk[dst] = saved_mk[src_rel]
      }
      if has_bones && saved_bones[src_rel] {
        bone_insts.add(dst)
      }
    }
  }
}
