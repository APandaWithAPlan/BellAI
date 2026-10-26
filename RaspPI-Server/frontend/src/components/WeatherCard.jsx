import { Card, CardHeader, CardTitle, CardContent } from "./ui/card"

function WeatherCard({ date, time, period }) {
  return (
    <Card className="rounded-xl border border-solid border-[#7d5070] bg-[#20151c] p-4 text-white shadow-lg">
      <CardHeader>
        <CardTitle className="flex items-baseline gap-2">
          <span className="text-6xl font-light">
            {time}
          </span>

          <span className="text-lg text-[#a35b89]">
            {period}
          </span>
        </CardTitle>
      </CardHeader>

      <CardContent>
        <p className="text-xs tracking-widest text-[#a35b89]">
          {date}
        </p>
      </CardContent>
    </Card>
  )
}

export default WeatherCard