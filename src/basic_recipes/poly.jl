"""
    poly(vertices, indices; kwargs...)
    poly(points; kwargs...)
    poly(shape; kwargs...)
    poly(mesh; kwargs...)

Plots a polygon based on the arguments given.
When vertices and indices are given, it functions similarly to `mesh`.
When points are given, it draws one polygon that connects all the points in order.
When a shape is given (essentially anything decomposable by `GeometryBasics`), it will plot `decompose(shape)`.

    poly(coordinates, connectivity; kwargs...)

Plots polygons, which are defined by
`coordinates` (the coordinates of the vertices) and
`connectivity` (the edges between the vertices).

## Attributes
$(ATTRIBUTES)
"""
@recipe(Poly) do scene
    Attributes(;
        color = theme(scene, :patchcolor),
        visible = theme(scene, :visible),
        strokecolor = theme(scene, :patchstrokecolor),
        colormap = theme(scene, :colormap),
        colorrange = automatic,
        strokewidth = theme(scene, :patchstrokewidth),
        shading = false,
        fxaa = true,
        linestyle = nothing,
        overdraw = false,
        transparency = false,
        cycle = [:color => :patchcolor],
        inspectable = theme(scene, :inspectable),
        space = :data
    )
end

const PolyElements = Union{Polygon, MultiPolygon, Circle, Rect, AbstractMesh, VecTypes, AbstractVector{<:VecTypes}}

convert_arguments(::Type{<: Poly}, v::AbstractVector{<: PolyElements}) = (v,)
convert_arguments(::Type{<: Poly}, v::Union{Polygon, MultiPolygon}) = (v,)

convert_arguments(::Type{<: Poly}, args...) = ([convert_arguments(Scatter, args...)[1]],)
function convert_arguments(::Type{<: Poly}, vertices::AbstractArray, indices::AbstractArray)
    m = GeometryBasics.Mesh(to_vertices(vertices), to_triangles(indices))
    return (m,)
end
convert_arguments(::Type{<: Poly}, m::GeometryBasics.Mesh) = (m,)

function plot!(plot::Poly{<: Tuple{Union{GeometryBasics.Mesh, GeometryPrimitive}}})
    mesh!(
        plot, plot[1],
        color = plot[:color], colormap = plot[:colormap], colorrange = plot[:colorrange],
        shading = plot[:shading], visible = plot[:visible], overdraw = plot[:overdraw],
        inspectable = plot[:inspectable], transparency = plot[:transparency],
        space = plot[:space]
    )
    wireframe!(
        plot, plot[1],
        color = plot[:strokecolor], linestyle = plot[:linestyle], space = plot[:space],
        linewidth = plot[:strokewidth], visible = plot[:visible], overdraw = plot[:overdraw],
        inspectable = plot[:inspectable],
        transparency = plot[:transparency],
    )
end

# Poly conversion
poly_convert(geometries) = triangle_mesh.(geometries)
poly_convert(meshes::AbstractVector{<:AbstractMesh}) = meshes
poly_convert(polys::AbstractVector{<:Polygon}) = triangle_mesh.(polys)
function poly_convert(multipolygons::AbstractVector{<:MultiPolygon})
    return [merge(triangle_mesh.(multipoly.polygons)) for multipoly in multipolygons]
end

poly_convert(mesh::GeometryBasics.Mesh) = mesh

poly_convert(polygon::Polygon) = triangle_mesh(polygon)

function poly_convert(polygon::AbstractVector{<: VecTypes})
    return poly_convert([convert_arguments(Scatter, polygon)[1]])
end

function poly_convert(polygons::AbstractVector{<: AbstractVector{<: VecTypes}})
    return map(polygons) do poly
        point2f = convert(Vector{Point2f}, poly)
        faces = GeometryBasics.earcut_triangulate([point2f])
        return GeometryBasics.Mesh(point2f, faces)
    end
end

to_line_segments(polygon) = convert_arguments(PointBased(), polygon)[1]
# Need to explicitly overload for Mesh, since otherwise, Mesh will dispatch to AbstractVector
to_line_segments(polygon::GeometryBasics.Mesh) = convert_arguments(PointBased(), polygon)[1]

function to_line_segments(meshes::AbstractVector)
    line = Point2f[]
    for (i, mesh) in enumerate(meshes)
        points = to_line_segments(mesh)
        append!(line, points)
        # push!(line, points[1])
        # dont need to separate the last line segment
        if i != length(meshes)
            push!(line, Point2f(NaN))
        end
    end
    return line
end

function to_line_segments(polygon::AbstractVector{<: VecTypes})
    result = Point2f.(polygon)
    push!(result, polygon[1])
    return result
end

function plot!(plot::Poly{<: Tuple{<: Union{Polygon, AbstractVector{<: PolyElements}}}})
    geometries = plot[1]
    meshes = lift(poly_convert, geometries)
    mesh!(plot, meshes;
        visible = plot.visible,
        shading = plot.shading,
        color = plot.color,
        colormap = plot.colormap,
        colorrange = plot.colorrange,
        overdraw = plot.overdraw,
        fxaa = plot.fxaa,
        transparency = plot.transparency,
        inspectable = plot.inspectable,
        space = plot.space
    )
    outline = lift(to_line_segments, geometries)
    stroke = lift(outline, plot.strokecolor) do outline, sc
        if !(meshes[] isa Mesh) && meshes[] isa AbstractVector && sc isa AbstractVector && length(sc) == length(meshes[])
            idx = 1
            return map(outline) do point
                if isnan(point)
                    idx += 1
                end
                return sc[idx]
            end
        else
            return sc
        end
    end

    lines!(
        plot, outline, visible = plot.visible,
        color = stroke, linestyle = plot.linestyle,
        linewidth = plot.strokewidth, space = plot.space,
        overdraw = plot.overdraw, transparency = plot.transparency,
        inspectable = plot.inspectable, depth_shift = -1f-5
    )
end
function calculated_attributes!(::Type{<:Mesh{<: Tuple{<: AbstractVector{P}}}}, attr) where P <: Union{AbstractMesh, Polygon}
    # Need to overload this, since the generic version for Mesh isn't needed
    return nothing
end
function plot!(plot::Mesh{<: Tuple{<: AbstractVector{P}}}) where P <: Union{AbstractMesh, Polygon}
    meshes = plot[1]
    color_node = plot.color
    attributes = Attributes(
        visible = plot.visible, shading = plot.shading, fxaa = plot.fxaa,
        inspectable = plot.inspectable, transparency = plot.transparency,
        space = plot.space
    )

    attributes[:colormap] = get(plot, :colormap, nothing)
    attributes[:colorrange] = get(plot, :colorrange, nothing)
    # needs to happen manually, since we convert patterns to matrix of colors early in recipe
    attributes[:fetch_pixel] = map(plot.color) do color
        color isa AbstractPattern
    end

    num_meshes = Observable(Int[])
    map(meshes) do meshes
        # TODO use change observable!
        new_lengths = length.(coordinates.(meshes))
        if num_meshes[] != new_lengths
            num_meshes[] = new_lengths
        end
        return
    end
    mesh_colors = Observable{Union{Matrix{RGBAf}, RGBColors}}()
    map!(mesh_colors, plot.color, num_meshes) do colors, num_meshes
        # one mesh per color
        c_converted = to_color(colors)
        if c_converted isa AbstractVector && length(c_converted) == length(num_meshes)
            result = similar(c_converted, sum(num_meshes))
            i = 1
            for (cs, len) in zip(c_converted, num_meshes)
                for j in 1:len
                    result[i] = cs
                    i += 1
                end
            end
            return result
        else
            return c_converted
        end
    end
    attributes[:color] = mesh_colors
    lift(meshes) do meshes
        m = merge(GeometryBasics.mesh.(meshes))
        attributes[:faces] = decompose(GLTriangleFace, m)
        attributes[:vertices] = decompose(Point, m)
        return
    end
    p = mesh!(plot, attributes)
end
