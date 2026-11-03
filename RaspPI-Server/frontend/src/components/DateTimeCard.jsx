import { Card, CardHeader, CardTitle, CardContent } from "./ui/card"

function DateTimeCard({ date, time, period }) {
  return (
    <Card className="h-full rounded-xl gap-3 border border-solid border-[#fbcfe8] bg-[#ffffff] p-4 text-black shadow-lg">
      <CardHeader>
        <CardTitle className="flex items-baseline gap-2">
          <span className="text-6xl font-light">
            {time}
          </span>

          <span className="text-lg text-[#be185d]">
            {period}
          </span>
        </CardTitle>
      </CardHeader>

      <CardContent>
        <p className="text-sm tracking-widest text-[#be185d]">
          {date}
        </p>
      </CardContent>
    </Card>
  )
}

export default DateTimeCard