.pragma library

function update(snapshot, previous) {
  const elapsed = previous ? snapshot.now - previous.now : 0
  const counters = Object.create(null)
  const rows = snapshot.rows.map(fields => {
    const [pid, parent, name, executable, state, start, ticks, pages, disk] = fields
    const key = pid + ":" + start
    const prior = previous && previous.counters[key]
    counters[key] = [ticks, disk]
    const cleanPath = executable.replace(/ \(deleted\)$/, "")
    const program = cleanPath ? cleanPath.split("/").pop() || name : name
    return {
      key, pid, parent, name, program, executable: cleanPath, state,
      age: Math.max(0, snapshot.uptime - start / snapshot.ticks),
      cpu: prior && elapsed > 0 && ticks >= prior[0] ? 100 * (ticks - prior[0]) / snapshot.ticks / elapsed : null,
      ram: pages * snapshot.pageSize,
      io: prior && elapsed > 0 && disk !== null && prior[1] !== null && disk >= prior[1]
          ? (disk - prior[1]) / elapsed : null
    }
  })
  return { now: snapshot.now, rows, counters, truncated: snapshot.truncated }
}

function contains(row, query) {
  return [row.name, row.program, row.executable, String(row.pid), String(row.parent)]
    .some(value => value.toLowerCase().includes(query))
}

function matches(row, filter) {
  if (filter === "cpuActive") return row.cpu > 0
  if (filter === "memoryActive") return row.ram > 0
  if (filter === "diskActive") return row.io > 0
  if (filter === "running") return row.state === "R"
  return true
}

function total(rows, field) {
  const values = rows.map(row => row[field]).filter(value => value !== null)
  return values.length ? values.reduce((sum, value) => sum + value, 0) : null
}

function build(rows, search, filter, sort, mode, expanded) {
  const query = search.trim().toLowerCase()
  const byPid = new Map(rows.map(row => [row.pid, row]))
  const selected = rows.filter(row => matches(row, filter)
    && (!query || contains(row, query)
        || (mode === "family" && byPid.has(row.parent) && contains(byPid.get(row.parent), query))))
  function compare(a, b) {
    if (sort === "name")
      return a.name.localeCompare(b.name) || (a.pid || 0) - (b.pid || 0)
    const first = a[sort] === null ? -1 : a[sort]
    const second = b[sort] === null ? -1 : b[sort]
    return second - first || a.name.localeCompare(b.name) || (a.pid || 0) - (b.pid || 0)
  }
  selected.sort(compare)
  if (mode === "single")
    return { rows: selected, count: selected.length }

  const groups = new Map()
  for (const row of selected) {
    const parent = byPid.get(row.parent)
    const key = mode === "program" ? row.executable || row.name : parent ? parent.key : String(row.parent)
    if (!groups.has(key))
      groups.set(key, { parent, parentPid: row.parent, items: [] })
    groups.get(key).items.push(row)
  }
  const summary = []
  for (const [key, group] of groups) {
    const {parent, parentPid, items} = group
    if (items.length === 1) {
      summary.push(items[0])
      continue
    }
    summary.push({
      key: mode + ":" + key, group: true, name: mode === "program" ? items[0].program : parent ? parent.name : "",
      executable: mode === "program" ? items[0].executable : "",
      parentPid: mode === "family" ? parentPid : null, items,
      age: Math.max(...items.map(row => row.age)),
      cpu: total(items, "cpu"), ram: total(items, "ram"), io: total(items, "io")
    })
  }
  summary.sort(compare)
  const visible = []
  for (const row of summary) {
    visible.push(row)
    if (row.group && expanded[row.key]) {
      for (const item of row.items)
        visible.push(Object.assign({}, item, {child: true}))
    }
  }
  return { count: selected.length, rows: visible }
}
