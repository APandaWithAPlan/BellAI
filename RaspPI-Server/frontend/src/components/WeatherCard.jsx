import { Card, CardHeader, CardTitle, CardContent } from "./ui/card"
import { Separator } from "@/components/ui/separator"
import { Cloud } from "lucide-react"

function WeatherCard({ temperature, temperature_unit, description, high, low, hum, location }) {
  return (
    <Card className="h-full gap-3 rounded-xl border border-[#fbcfe8] bg-white p-4 text-black shadow-lg">

      <CardHeader className="p-0">
        <CardTitle className="flex items-center justify-between">

          <span className="text-5xl font-light">
            {temperature}{temperature_unit}
          </span>

          <Cloud
            size={36}
            strokeWidth={1.5}
            className="text-[#54b7e8]"
          />

        </CardTitle>

        <p className="text-xs text-[#be185d]">
          {description}
        </p>
      </CardHeader>

      <Separator className="bg-[#fbcfe8]" />

      <CardContent className="space-y-3 p-0">

        <div className="grid grid-cols-3 gap-4">
          <div>
            <p className="text-xs text-[#be185d]">HIGH</p>
            <p className="font-semibold">{high}{temperature_unit}</p>
          </div>

          <div>
            <p className="text-xs text-[#be185d]">LOW</p>
            <p className="font-semibold">{low}{temperature_unit}</p>
          </div>

          <div className="text-right">
            <p className="text-xs text-[#be185d]">HUM</p>
            <p className="font-semibold">{hum}%</p>
          </div>
        </div>

        <p className="text-xs text-[#be185d]">
          {location}
        </p>

      </CardContent>
    </Card>
  )
}

export default WeatherCard