import { useState } from "react"
import { Card, CardContent } from "./ui/card"
import { Checkbox } from "@/components/ui/checkbox"

function ToDoCard({ task }) {
  const [completed, setCompleted] = useState(false)

  return (
    
    <div className="flex items-center gap-3 border-b border-[#39212e] px-4 py-3 last:border-b-0">

      <Checkbox checked={completed} onCheckedChange={setCompleted} className="rounded border-[#7d5070] data-checked:border-[#34d399] data-checked:bg-[#34d399]"/>

      <span className={`text-sm ${ completed ? "text-[#a35b89] line-through" : "text-white" }`}>
        {task}
      </span>

    </div>
  )
}

export default ToDoCard