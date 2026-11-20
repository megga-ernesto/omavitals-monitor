import QtQuick

Canvas {
  id: chart

  required property var points
  required property color tint
  property real ceiling: 0
  property int capacity: 30

  onPointsChanged: requestPaint()
  onTintChanged: requestPaint()
  onCeilingChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onVisibleChanged: if (visible) requestPaint()

  onPaint: {
    const ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    if (width < 4 || height < 8)
      return

    ctx.strokeStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.13)
    ctx.lineWidth = 1
    for (const fraction of [0.17, 0.5, 0.83]) {
      ctx.beginPath()
      ctx.moveTo(0, height * fraction)
      ctx.lineTo(width, height * fraction)
      ctx.stroke()
    }

    const valid = points.filter(value => value !== null)
    if (!valid.length)
      return
    const high = ceiling > 0 ? ceiling : Math.max(1, ...valid)
    const low = ceiling > 0 ? 0 : Math.min(0, ...valid)
    const step = (width - 4) / (capacity - 1)
    const origin = 2 + (capacity - points.length) * step
    const gradient = ctx.createLinearGradient(0, 0, 0, height)
    gradient.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, 0.25))
    gradient.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0.02))
    const segments = []
    let segment = []
    for (let i = 0; i < points.length; ++i) {
      if (points[i] === null) {
        if (segment.length) segments.push(segment)
        segment = []
        continue
      }
      const fraction = Math.max(0, Math.min(1, (points[i] - low) / (high - low)))
      segment.push([origin + i * step, 3 + (1 - fraction) * (height - 6)])
    }
    if (segment.length) segments.push(segment)

    ctx.lineWidth = 1.7
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.strokeStyle = tint
    for (const line of segments) {
      const first = line[0]
      const last = line[line.length - 1]
      if (line.length === 1) {
        ctx.fillStyle = tint
        ctx.beginPath()
        ctx.arc(first[0], first[1], 1.8, 0, 2 * Math.PI)
        ctx.fill()
        continue
      }

      ctx.beginPath()
      ctx.moveTo(first[0], first[1])
      for (const point of line.slice(1))
        ctx.lineTo(point[0], point[1])
      ctx.lineTo(last[0], height)
      ctx.lineTo(first[0], height)
      ctx.closePath()
      ctx.fillStyle = gradient
      ctx.fill()

      ctx.beginPath()
      ctx.moveTo(first[0], first[1])
      for (const point of line.slice(1))
        ctx.lineTo(point[0], point[1])
      ctx.stroke()
    }
  }
}
