import { NavLink } from "react-router"
import { House, Lightbulb, Calendar, Flower } from "lucide-react"

function NavBar() {
  return (
    <nav className="grid h-16 grid-cols-4 border-t border-[#7d5070] bg-[#150d10]">

      <NavLink to="/" end className={({ isActive }) => `flex flex-col items-center justify-center ${ isActive ? "text-[#f472b6] underline underline-offset-12" : "text-[#7d5070] hover:text-white"}`}>
        <House size={24} strokeWidth={1.5} />
        <span>Home</span>
      </NavLink>

      <NavLink to="/devices" className={({ isActive }) => `flex flex-col items-center justify-center ${ isActive ? "text-[#f472b6] underline underline-offset-12" : "text-[#7d5070] hover:text-white"}`}>
        <Lightbulb size={24} strokeWidth={1.5} />
        <span>Devices</span>
      </NavLink>

      <NavLink to="/life" className={({ isActive }) => `flex flex-col items-center justify-center ${ isActive ? "text-[#f472b6] underline underline-offset-12" : "text-[#7d5070] hover:text-white"}`}>
        <Calendar size={24} strokeWidth={1.5} />
        <span>Life</span>
      </NavLink>

      <NavLink to="/bellai" className={({ isActive }) => `flex flex-col items-center justify-center ${ isActive ? "text-[#f472b6] underline underline-offset-12" : "text-[#7d5070] hover:text-white"}`}>
        <Flower size={24} strokeWidth={1.5} />
        <span>BellAI</span>
      </NavLink>

    </nav>
  )
}

export default NavBar