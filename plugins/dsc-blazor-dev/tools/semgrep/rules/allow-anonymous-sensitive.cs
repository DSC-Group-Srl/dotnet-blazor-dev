using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class EmployeesController : ControllerBase
{
    /// ruleid: dsc-allow-anonymous-sensitive
    [AllowAnonymous]
    [HttpPost]
    public IActionResult Create(EmployeeDto dto)
    {
        return Ok();
    }

    /// ruleid: dsc-allow-anonymous-sensitive
    [AllowAnonymous]
    [HttpDelete("{id:int}")]
    public IActionResult Delete(int id)
    {
        return NoContent();
    }

    /// ok: dsc-allow-anonymous-sensitive
    [AllowAnonymous]
    [HttpGet("public-info")]
    public IActionResult PublicInfo()
    {
        return Ok();
    }

    /// ok: dsc-allow-anonymous-sensitive
    [HttpPost("secure")]
    public IActionResult Secure(EmployeeDto dto)
    {
        return Ok();
    }
}

/// ruleid: dsc-allow-anonymous-sensitive
[AllowAnonymous]
public class OpenController : ControllerBase
{
    public IActionResult Index()
    {
        return Ok();
    }
}

public static class Endpoints
{
    public static void Map(WebApplication app)
    {
        /// ruleid: dsc-allow-anonymous-sensitive
        app.MapPost("/api/tenants", CreateTenant).AllowAnonymous();

        /// ok: dsc-allow-anonymous-sensitive
        app.MapGet("/health", () => Results.Ok()).AllowAnonymous();
    }
}

public class SyncFunctions
{
    [Function("SyncEmployees")]
    public async Task<IActionResult> Run(
        /// ruleid: dsc-function-anonymous-http-trigger
        [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequest req)
    {
        return new OkResult();
    }

    [Function("SyncDepartments")]
    public async Task<IActionResult> RunSecure(
        /// ok: dsc-function-anonymous-http-trigger
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
    {
        return new OkResult();
    }
}
