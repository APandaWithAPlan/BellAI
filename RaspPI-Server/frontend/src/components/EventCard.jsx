import { Card, CardContent } from "./ui/card"
import { Separator } from "@/components/ui/separator"
import { EighthNote, Pause, SkipForward, SkipBack } from "lucide-react"

function EventCard({ time, timeUntil, title }) {
  return (
    <Card className="rounded-xl border border-[#7d5070] bg-[#20151c] p-4 text-white shadow-lg">
      <CardContent className="flex items-center justify-between gap-4 p-0">

        <div className="flex min-w-0 items-center gap-4">
            
            <Separator orientation="vertical" />

          <div className="min-w-0">
            <p className="text-sm text-[#f472b6]">
              {time} · {timeUntil} min
            </p>
            <p className="text-lg font-semibold">
                {title}
            </p>
          </div>

        </div>

      </CardContent>
    </Card>
  )
}

export default EventCard