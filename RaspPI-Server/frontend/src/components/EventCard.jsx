import { Card, CardContent } from "./ui/card"
import { Separator } from "@/components/ui/separator"

function EventCard({ time, timeUntil, title }) {
  return (
    <Card className="rounded-xl border border-[#fbcfe8] bg-white p-4 text-black shadow-lg">
      <CardContent className="flex items-center justify-between gap-4 p-0">

        <div className="flex min-w-0 items-center gap-4">
            
            <Separator orientation="vertical" className="h-12! bg-[#f472b6]!"/>

          <div className="min-w-0">

            <p className="text-lg font-semibold">
                {title}
            </p>

            <p className="text-sm text-[#be185d]">
              {time} · {timeUntil}
            </p>

          </div>

        </div>

      </CardContent>
    </Card>
  )
}

export default EventCard