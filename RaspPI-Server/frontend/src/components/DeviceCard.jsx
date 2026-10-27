import { Card, CardContent } from "./ui/card"

function DeviceCard({ icon: Icon, value, label, color }) {
  return (
    <Card className="h-full rounded-xl border border-[#7d5070] bg-[#20151c] text-white">
      <CardContent className="flex flex-col items-center justify-center gap-2 p-4">

        <div className="rounded-lg bg-[#39212e] p-3" style={{ backgroundColor: `color-mix(in srgb, ${color} 15%, transparent)` }}>
          <Icon size={24} color={color} />
        </div>

        <p className="text-sm font-semibold">
          {value}
        </p>

        <p className="text-xs text-[#a35b89]">
          {label}
        </p>

      </CardContent>
    </Card>
  )
}

export default DeviceCard