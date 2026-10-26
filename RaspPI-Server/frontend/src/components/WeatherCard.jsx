import { Card, CardHeader, CardTitle, CardContent } from "./ui/card"
import { Separator } from "@/components/ui/separator"
import { Cloud } from "lucide-react"

function WeatherCard({ temperature, description, high, low, hum, location }) {
  return (
    <Card className="h-full gap-3 rounded-xl border border-[#7d5070] bg-[#20151c] p-4 text-white shadow-lg">

      <CardHeader className="p-0">
        <CardTitle className="flex items-center justify-between">

          <span className="text-5xl font-light">
            {temperature}°
          </span>

          <Cloud
            size={36}
            strokeWidth={1.5}
            className="text-[#54b7e8]"
          />

        </CardTitle>

        <p className="text-xs text-[#a35b89]">
          {description}
        </p>
      </CardHeader>

      <Separator className="bg-[#39212e]" />

      <CardContent className="space-y-3 p-0">

        <div className="grid grid-cols-3 gap-4">
          <div>
            <p className="text-xs text-[#a35b89]">HIGH</p>
            <p className="font-semibold">{high}°</p>
          </div>

          <div>
            <p className="text-xs text-[#a35b89]">LOW</p>
            <p className="font-semibold">{low}°</p>
          </div>

          <div className="text-right">
            <p className="text-xs text-[#a35b89]">HUM</p>
            <p className="font-semibold">{hum}%</p>
          </div>
        </div>

        <p className="text-xs text-[#a35b89]">
          {location}
        </p>

      </CardContent>
    </Card>
  )
}

export default WeatherCard