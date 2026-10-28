import { Card, CardContent } from "./ui/card"
import { Progress } from "@/components/ui/progress"

function EventCard({ seller, item, arrivalTime, progress }) {
  return (
    <Card className="rounded-xl border border-[#7d5070] bg-[#20151c] p-4 text-white shadow-lg">
      <CardContent className="p-0">

        <div className="flex items-start justify-between">

            <p className="text-lg font-semibold">
                {seller}
            </p>

            <p className="text-sm text-[#f472b6]">
                {arrivalTime}
            </p>

        </div>

            <p className="text-sm text-[#a35b89]">
                {item}
            </p>

            <Progress value={progress} className="mt-2 bg-[#39212e] [&_[data-slot=progress-indicator]]:bg-[#34d399]"/>

      </CardContent>
    </Card>
  )
}

export default EventCard