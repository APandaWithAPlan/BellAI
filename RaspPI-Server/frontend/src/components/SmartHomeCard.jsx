import { Card, CardContent } from "./ui/card"
import { Switch } from "@/components/ui/switch"

function SmartHomeCard({ icon: Icon, location, color, isOn, onToggle}) {
  return (
    <Card className="w-54 rounded-xl border border-[#7d5070] bg-[#20151c]">
      <CardContent className="flex flex-col gap-4 px-4">

        <div className="flex items-start justify-between">

        
            <div className="rounded-xl p-3" style={{ backgroundColor: `color-mix(in srgb, ${color} 15%, transparent)` }}>
                <Icon size={24} color={color}/>
            </div>

            <Switch checked={isOn} onCheckedChange={onToggle}/>

        </div>

        <div className="flex flex-col gap-1">
          <p className="text-sm font-semibold text-[#a35b89]">
            {location}
          </p>
        </div>

      </CardContent>
    </Card>
  )
}

export default SmartHomeCard